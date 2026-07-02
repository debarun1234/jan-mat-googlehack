"""
BigQuery client for data warehouse operations.
Implements schema validation, deduplication, and transactional safety.
"""

import logging
from typing import List, Dict, Any, Optional
from datetime import datetime

from google.cloud import bigquery
from google.api_core import retry, exceptions
from google.cloud.bigquery import SchemaField, LoadJobConfig

from app.config.settings import get_settings
from app.utils.errors import DatabaseError, ErrorCode


logger = logging.getLogger(__name__)


class BigQuerySchema:
    """BigQuery schema definitions."""
    
    # Main grievances table schema
    CITIZEN_GRIEVANCES_SCHEMA = [
        SchemaField("submission_id", "STRING", mode="REQUIRED"),
        SchemaField("gcs_uri", "STRING", mode="REQUIRED"),
        SchemaField("input_type", "STRING", mode="REQUIRED"),
        SchemaField("raw_text", "STRING", mode="REQUIRED"),
        SchemaField("category", "STRING", mode="REQUIRED"),
        SchemaField("priority", "STRING", mode="NULLABLE"),
        SchemaField("sentiment", "STRING", mode="NULLABLE"),
        SchemaField("summary_en", "STRING", mode="REQUIRED"),
        SchemaField("confidence_score", "FLOAT64", mode="REQUIRED"),
        SchemaField("latitude", "FLOAT64", mode="NULLABLE"),
        SchemaField("longitude", "FLOAT64", mode="NULLABLE"),
        SchemaField("hotspot_id", "STRING", mode="NULLABLE"),
        SchemaField("priority_score", "FLOAT64", mode="NULLABLE"),
        SchemaField("evidence_log", "STRING", mode="NULLABLE"),
        SchemaField("submitted_at", "TIMESTAMP", mode="REQUIRED"),
        SchemaField("processing_completed_at", "TIMESTAMP", mode="REQUIRED"),
        SchemaField("pipeline_version", "STRING", mode="NULLABLE"),
    ]
    
    # Audit log table schema
    PIPELINE_AUDIT_SCHEMA = [
        SchemaField("audit_id", "STRING", mode="REQUIRED"),
        SchemaField("request_id", "STRING", mode="REQUIRED"),
        SchemaField("upload_status", "STRING", mode="REQUIRED"),
        SchemaField("extract_status", "STRING", mode="REQUIRED"),
        SchemaField("transform_status", "STRING", mode="REQUIRED"),
        SchemaField("ai_status", "STRING", mode="REQUIRED"),
        SchemaField("load_status", "STRING", mode="REQUIRED"),
        SchemaField("error_code", "STRING", mode="NULLABLE"),
        SchemaField("error_message", "STRING", mode="NULLABLE"),
        SchemaField("processing_time_ms", "INTEGER", mode="NULLABLE"),
        SchemaField("file_size_bytes", "INTEGER", mode="NULLABLE"),
        SchemaField("input_type", "STRING", mode="NULLABLE"),
        SchemaField("created_at", "TIMESTAMP", mode="REQUIRED"),
        SchemaField("updated_at", "TIMESTAMP", mode="REQUIRED"),
    ]


class BigQueryClient:
    """Production BigQuery client."""
    
    def __init__(self):
        self.settings = get_settings()
        self.client = bigquery.Client(project=self.settings.cloud.gcp_project_id)
        self.dataset_id = self.settings.cloud.bigquery_dataset
        self.table_grievances = self.settings.cloud.bigquery_table_grievances
        self.table_audit = self.settings.cloud.bigquery_table_audit
        
        # Verify dataset exists
        self._ensure_dataset_exists()
        self._ensure_tables_exist()
    
    def _ensure_dataset_exists(self):
        """Verify dataset exists, create if not."""
        
        try:
            dataset = self.client.get_dataset(self.dataset_id)
            logger.info(f"Dataset {self.dataset_id} exists")
        
        except exceptions.NotFound:
            logger.warning(f"Dataset {self.dataset_id} not found, creating...")
            
            dataset = bigquery.Dataset(
                f"{self.settings.cloud.gcp_project_id}.{self.dataset_id}"
            )
            dataset.location = self.settings.database.bigquery_location
            
            try:
                dataset = self.client.create_dataset(dataset, timeout=30)
                logger.info(f"Dataset {self.dataset_id} created")
            except Exception as e:
                raise DatabaseError(
                    message=f"Failed to create dataset: {str(e)}",
                    error_code=ErrorCode.BIGQUERY_PERMISSION_DENIED,
                    original_exception=e
                )
    
    def _ensure_tables_exist(self):
        """Verify tables exist, create if not."""
        
        tables_to_create = [
            (self.table_grievances, BigQuerySchema.CITIZEN_GRIEVANCES_SCHEMA),
            (self.table_audit, BigQuerySchema.PIPELINE_AUDIT_SCHEMA),
        ]
        
        for table_name, schema in tables_to_create:
            table_id = f"{self.settings.cloud.gcp_project_id}.{self.dataset_id}.{table_name}"
            
            try:
                table = self.client.get_table(table_id)
                logger.info(f"Table {table_name} exists")
            
            except exceptions.NotFound:
                logger.warning(f"Table {table_name} not found, creating...")
                
                table = bigquery.Table(table_id, schema=schema)
                
                # Set partitioning for main table
                if table_name == self.table_grievances:
                    table.time_partitioning = bigquery.TimePartitioning(
                        type_=bigquery.TimePartitioningType.DAY,
                        field="submitted_at"
                    )
                    table.clustering_fields = ["category", "hotspot_id"]
                
                try:
                    table = self.client.create_table(table)
                    logger.info(f"Table {table_name} created")
                except Exception as e:
                    raise DatabaseError(
                        message=f"Failed to create table {table_name}: {str(e)}",
                        error_code=ErrorCode.BIGQUERY_SCHEMA_MISMATCH,
                        original_exception=e
                    )
    
    def _validate_row_schema(self, row: Dict[str, Any], schema: List[SchemaField]) -> bool:
        """Validate row against schema."""
        
        required_fields = {field.name for field in schema if field.mode == "REQUIRED"}
        row_fields = set(row.keys())
        
        # Check all required fields present
        missing = required_fields - row_fields
        if missing:
            logger.error(f"Missing required fields: {missing}")
            return False
        
        # Check for extra fields
        allowed_fields = {field.name for field in schema}
        extra = row_fields - allowed_fields
        if extra:
            logger.warning(f"Extra fields in row: {extra}")
            # Don't fail, just log (extra fields might be added for future compatibility)
        
        return True
    
    @retry.Retry(deadline=30)
    def insert_rows(
        self,
        table_name: str,
        rows: List[Dict[str, Any]],
        request_id: Optional[str] = None,
        skip_invalid_rows: bool = False,
        fail_on_duplicate: bool = True
    ) -> Dict[str, Any]:
        """
        Insert rows into BigQuery table.
        
        Args:
            table_name: Target table name
            rows: List of row dictionaries
            request_id: Optional request ID for logging
            skip_invalid_rows: Skip rows that don't match schema
            fail_on_duplicate: Fail if duplicate submission_id detected
        
        Returns:
            Insert result with counts
        
        Raises:
            DatabaseError: If insert fails
        """
        
        if not rows:
            return {"inserted": 0, "failed": 0, "skipped": 0}
        
        try:
            table_id = f"{self.settings.cloud.gcp_project_id}.{self.dataset_id}.{table_name}"
            
            # Validate schema
            schema = (
                BigQuerySchema.CITIZEN_GRIEVANCES_SCHEMA
                if table_name == self.table_grievances
                else BigQuerySchema.PIPELINE_AUDIT_SCHEMA
            )
            
            # Validate all rows
            valid_rows = []
            invalid_count = 0
            
            for row in rows:
                if self._validate_row_schema(row, schema):
                    valid_rows.append(row)
                else:
                    invalid_count += 1
                    if not skip_invalid_rows:
                        raise DatabaseError(
                            message=f"Row schema validation failed",
                            error_code=ErrorCode.BIGQUERY_SCHEMA_MISMATCH,
                            request_id=request_id,
                            details={"invalid_row": row}
                        )
            
            if not valid_rows:
                raise DatabaseError(
                    message="No valid rows to insert",
                    error_code=ErrorCode.BIGQUERY_SCHEMA_MISMATCH,
                    request_id=request_id
                )
            
            # Check for duplicates if required
            if fail_on_duplicate and table_name == self.table_grievances:
                submission_ids = [
                    row.get("submission_id") for row in valid_rows
                ]
                if len(submission_ids) != len(set(submission_ids)):
                    raise DatabaseError(
                        message="Duplicate submission_id in batch",
                        error_code=ErrorCode.BIGQUERY_DUPLICATE_KEY,
                        request_id=request_id,
                        retry_eligible=False
                    )
            
            # Insert rows
            errors = self.client.insert_rows_json(
                table_id,
                valid_rows,
                timeout=self.settings.database.bigquery_timeout_seconds
            )
            
            if errors:
                # Some rows failed
                error_details = []
                for error in errors:
                    error_details.append({
                        "index": error.get("index"),
                        "message": error.get("errors", [{}])[0].get("message", "Unknown error")
                    })
                
                logger.error(
                    f"BigQuery insert had errors",
                    request_id=request_id,
                    errors=error_details
                )
                
                raise DatabaseError(
                    message=f"BigQuery insert failed for {len(errors)} rows",
                    error_code=ErrorCode.BIGQUERY_INSERT_FAILED,
                    request_id=request_id,
                    details={"error_count": len(errors)}
                )
            
            logger.info(
                f"Rows inserted successfully",
                request_id=request_id,
                table=table_name,
                row_count=len(valid_rows),
                invalid_count=invalid_count
            )
            
            return {
                "inserted": len(valid_rows),
                "failed": 0,
                "skipped": invalid_count,
                "table": table_name
            }
        
        except exceptions.GoogleCloudError as e:
            if "quotaExceeded" in str(e):
                error_code = ErrorCode.BIGQUERY_QUOTA_EXCEEDED
            elif "permission denied" in str(e):
                error_code = ErrorCode.BIGQUERY_PERMISSION_DENIED
            else:
                error_code = ErrorCode.BIGQUERY_INSERT_FAILED
            
            raise DatabaseError(
                message=f"BigQuery error: {str(e)}",
                error_code=error_code,
                request_id=request_id,
                original_exception=e
            )
        
        except DatabaseError:
            raise
        
        except Exception as e:
            raise DatabaseError(
                message=f"Unexpected database error: {str(e)}",
                error_code=ErrorCode.BIGQUERY_INSERT_FAILED,
                request_id=request_id,
                original_exception=e
            )
    
    def query_deduplication_check(
        self,
        submission_id: str
    ) -> bool:
        """Check if submission_id already exists."""
        
        try:
            query = f"""
            SELECT COUNT(*) as count
            FROM `{self.settings.cloud.gcp_project_id}.{self.dataset_id}.{self.table_grievances}`
            WHERE submission_id = @submission_id
            """
            
            job_config = bigquery.QueryJobConfig(
                query_parameters=[
                    bigquery.ScalarQueryParameter("submission_id", "STRING", submission_id)
                ]
            )
            
            query_job = self.client.query(
                query,
                job_config=job_config,
                timeout=10
            )
            
            results = query_job.result()
            count = list(results)[0].count
            
            return count > 0
        
        except Exception as e:
            logger.error(f"Deduplication check failed: {str(e)}")
            return False


def get_bigquery_client() -> BigQueryClient:
    """Get or create BigQuery client (singleton pattern)."""
    if not hasattr(get_bigquery_client, "_instance"):
        get_bigquery_client._instance = BigQueryClient()
    return get_bigquery_client._instance
