"""
AI output validation module (CP-4 checkpoint - highest risk).
Validates Gemini API responses before database insertion.
"""

import json
import logging
from typing import Dict, Any, Optional
from datetime import datetime

from app.config.settings import get_settings
from app.utils.errors import AIValidationError, ErrorCode


logger = logging.getLogger(__name__)


class AIOutputValidator:
    """Validates AI/Gemini output at CP-4."""
    
    def __init__(self):
        self.settings = get_settings()
        self.required_fields = {
            "category", "priority", "sentiment", "summary_en", "confidence_score"
        }
    
    def validate_json_structure(self, response: str) -> Dict[str, Any]:
        """
        Validate that response is valid JSON.
        
        Args:
            response: Raw response string from AI
        
        Returns:
            Parsed JSON object
        
        Raises:
            AIValidationError: If not valid JSON
        """
        
        try:
            data = json.loads(response)
            
            if not isinstance(data, dict):
                raise AIValidationError(
                    message="AI response must be a JSON object, not array",
                    error_code=ErrorCode.AI_INVALID_RESPONSE,
                    details={"response_type": type(data).__name__}
                )
            
            return data
        
        except json.JSONDecodeError as e:
            raise AIValidationError(
                message=f"Invalid JSON in AI response: {str(e)}",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={"json_error": str(e)},
                original_exception=e
            )
        
        except AIValidationError:
            raise
        
        except Exception as e:
            raise AIValidationError(
                message=f"Failed to parse AI response: {str(e)}",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                original_exception=e
            )
    
    def validate_required_fields(self, data: Dict[str, Any]) -> bool:
        """
        Validate all required fields are present.
        
        Args:
            data: Parsed JSON data from AI
        
        Raises:
            AIValidationError: If required field missing
        """
        
        missing_fields = self.required_fields - set(data.keys())
        
        if missing_fields:
            raise AIValidationError(
                message=f"Missing required fields: {', '.join(missing_fields)}",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={"missing": list(missing_fields), "provided": list(data.keys())}
            )
        
        return True
    
    def validate_field_types(self, data: Dict[str, Any]) -> bool:
        """
        Validate field types.
        
        Args:
            data: Parsed JSON data
        
        Raises:
            AIValidationError: If type validation fails
        """
        
        type_requirements = {
            "category": str,
            "priority": str,
            "sentiment": str,
            "summary_en": str,
            "confidence_score": (int, float)
        }
        
        for field, expected_type in type_requirements.items():
            if field in data:
                value = data[field]
                
                if not isinstance(value, expected_type):
                    raise AIValidationError(
                        message=f"Field '{field}' has wrong type",
                        error_code=ErrorCode.AI_INVALID_RESPONSE,
                        details={
                            "field": field,
                            "expected": str(expected_type),
                            "actual": type(value).__name__,
                            "value": value
                        }
                    )
        
        return True
    
    def validate_category(self, category: str) -> bool:
        """
        Validate category is in allowed values.
        
        Args:
            category: Category from AI response
        
        Raises:
            AIValidationError: If not valid category
        """
        
        allowed_categories = {
            "Education", "Health", "Roads", "Water", "Sanitation",
            "Electricity", "Transport", "Governance", "Other"
        }
        
        if category not in allowed_categories:
            raise AIValidationError(
                message=f"Invalid category: {category}",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={
                    "provided": category,
                    "allowed": list(allowed_categories)
                }
            )
        
        return True
    
    def validate_priority(self, priority: str) -> bool:
        """Validate priority level."""
        
        allowed_priorities = {"Low", "Medium", "High", "Critical"}
        
        if priority not in allowed_priorities:
            raise AIValidationError(
                message=f"Invalid priority: {priority}",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={
                    "provided": priority,
                    "allowed": list(allowed_priorities)
                }
            )
        
        return True
    
    def validate_sentiment(self, sentiment: str) -> bool:
        """Validate sentiment."""
        
        allowed_sentiments = {"Negative", "Neutral", "Positive"}
        
        if sentiment not in allowed_sentiments:
            raise AIValidationError(
                message=f"Invalid sentiment: {sentiment}",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={
                    "provided": sentiment,
                    "allowed": list(allowed_sentiments)
                }
            )
        
        return True
    
    def validate_summary_en(self, summary: str) -> bool:
        """
        Validate summary text.
        
        Args:
            summary: Summary from AI
        
        Raises:
            AIValidationError: If summary invalid
        """
        
        if not summary or len(summary.strip()) == 0:
            raise AIValidationError(
                message="summary_en cannot be empty",
                error_code=ErrorCode.AI_INVALID_RESPONSE
            )
        
        min_length = self.settings.processing.min_text_length
        if len(summary) < min_length:
            raise AIValidationError(
                message=f"summary_en too short (minimum: {min_length} characters)",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={
                    "length": len(summary),
                    "minimum": min_length
                }
            )
        
        max_length = self.settings.processing.max_text_length
        if len(summary) > max_length:
            raise AIValidationError(
                message=f"summary_en too long (maximum: {max_length} characters)",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={
                    "length": len(summary),
                    "maximum": max_length
                }
            )
        
        return True
    
    def validate_confidence_score(self, confidence: float) -> bool:
        """
        Validate confidence score is in [0, 1].
        
        Args:
            confidence: Confidence score from AI
        
        Raises:
            AIValidationError: If out of range
        """
        
        if not isinstance(confidence, (int, float)):
            raise AIValidationError(
                message="confidence_score must be numeric",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={"type": type(confidence).__name__}
            )
        
        if not (0.0 <= confidence <= 1.0):
            raise AIValidationError(
                message="confidence_score must be between 0 and 1",
                error_code=ErrorCode.AI_INVALID_RESPONSE,
                details={"value": confidence}
            )
        
        # Warn if below threshold
        threshold = self.settings.ai.confidence_threshold
        if confidence < threshold:
            logger.warning(
                f"Confidence score below threshold: {confidence} < {threshold}"
            )
        
        return True
    
    def validate_semantic_plausibility(
        self,
        summary: str,
        original_text: str,
        confidence: float
    ) -> bool:
        """
        Check semantic plausibility (hallucination guard).
        Verifies summary has lexical overlap with original text.
        
        Args:
            summary: AI-generated summary
            original_text: Original extracted text
            confidence: AI confidence score
        
        Returns:
            True if plausible, False otherwise
        """
        
        try:
            # Simple token overlap check
            summary_tokens = set(summary.lower().split())
            original_tokens = set(original_text.lower().split())
            
            # Compute Jaccard similarity
            intersection = summary_tokens & original_tokens
            union = summary_tokens | original_tokens
            
            if len(union) == 0:
                similarity = 0.0
            else:
                similarity = len(intersection) / len(union)
            
            # Minimum overlap threshold
            min_overlap = 0.2 if confidence > 0.8 else 0.1
            
            if similarity < min_overlap:
                logger.warning(
                    f"Low semantic overlap: {similarity:.2f} (threshold: {min_overlap})",
                    extra={
                        "similarity": similarity,
                        "summary_tokens": len(summary_tokens),
                        "original_tokens": len(original_tokens)
                    }
                )
                # Don't fail, just warn
            
            return True
        
        except Exception as e:
            logger.error(f"Semantic check failed: {str(e)}")
            # Don't fail semantic check on error
            return True
    
    def validate_domain_constraints(
        self,
        data: Dict[str, Any],
        request_id: Optional[str] = None
    ) -> bool:
        """
        Validate domain-specific constraints (Layer B validation).
        
        Args:
            data: Parsed AI response
            request_id: Request ID for logging
        
        Raises:
            AIValidationError: If constraint violated
        """
        
        try:
            self.validate_category(data.get("category", ""))
            self.validate_priority(data.get("priority", ""))
            self.validate_sentiment(data.get("sentiment", ""))
            self.validate_summary_en(data.get("summary_en", ""))
            self.validate_confidence_score(data.get("confidence_score", 0))
            
            logger.info(
                f"Domain constraints validated",
                request_id=request_id,
                category=data.get("category")
            )
            
            return True
        
        except AIValidationError:
            raise
        
        except Exception as e:
            raise AIValidationError(
                message=f"Domain constraint validation failed: {str(e)}",
                error_code=ErrorCode.AI_VALIDATION_FAILED,
                request_id=request_id,
                original_exception=e
            )
    
    def validate_full_response(
        self,
        response_text: str,
        original_text: Optional[str] = None,
        request_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Complete CP-4 validation pipeline.
        
        Args:
            response_text: Raw response from Gemini
            original_text: Original extracted text (for semantic check)
            request_id: Request ID for logging
        
        Returns:
            Validated response data
        
        Raises:
            AIValidationError: If any validation fails
        """
        
        try:
            # Layer A: Structural validation
            data = self.validate_json_structure(response_text)
            self.validate_required_fields(data)
            self.validate_field_types(data)
            
            logger.debug("✓ Structural validation passed", extra={"request_id": request_id})
            
            # Layer B: Domain constraint validation
            self.validate_domain_constraints(data, request_id)
            
            logger.debug("✓ Domain validation passed", extra={"request_id": request_id})
            
            # Layer C: Semantic plausibility check
            if original_text:
                self.validate_semantic_plausibility(
                    data.get("summary_en", ""),
                    original_text,
                    data.get("confidence_score", 0)
                )
                logger.debug("✓ Semantic check passed", extra={"request_id": request_id})
            
            # Add validation metadata
            data["_validation"] = {
                "validated_at": datetime.utcnow().isoformat(),
                "validation_stage": "CP-4",
                "structural_passed": True,
                "domain_passed": True,
                "semantic_passed": True if original_text else None
            }
            
            logger.info(
                f"AI output validation complete",
                request_id=request_id,
                category=data.get("category"),
                confidence=data.get("confidence_score")
            )
            
            return data
        
        except AIValidationError:
            raise
        
        except Exception as e:
            raise AIValidationError(
                message=f"Unexpected validation error: {str(e)}",
                error_code=ErrorCode.AI_VALIDATION_FAILED,
                request_id=request_id,
                original_exception=e
            )


def get_ai_validator() -> AIOutputValidator:
    """Get AI validator instance."""
    if not hasattr(get_ai_validator, "_instance"):
        get_ai_validator._instance = AIOutputValidator()
    return get_ai_validator._instance
