"""
Google Cloud Pub/Sub client for asynchronous ETL pipeline.
Handles message publishing, dead letter queue routing, and retry logic.
"""

import json
import logging
from typing import Dict, Any, Optional
from datetime import datetime

from google.cloud import pubsub_v1
from google.api_core import exceptions

from app.config.settings import get_settings
from app.utils.errors import QueueError, ErrorCode


logger = logging.getLogger(__name__)


class PubSubClient:
    """Production Pub/Sub client for pipeline orchestration."""

    def __init__(self):
        self.settings = get_settings()
        self.publisher_client = pubsub_v1.PublisherClient()
        self.subscriber_client = pubsub_v1.SubscriberClient()

        # Topic paths
        self.topic_submissions = self.publisher_client.topic_path(
            self.settings.cloud.gcp_project_id,
            self.settings.cloud.pubsub_topic_submissions,
        )
        self.topic_dlq = self.publisher_client.topic_path(
            self.settings.cloud.gcp_project_id, self.settings.cloud.pubsub_topic_dlq
        )

        # Subscription path
        self.subscription_path = self.subscriber_client.subscription_path(
            self.settings.cloud.gcp_project_id, self.settings.cloud.pubsub_subscription
        )

        # Verify topics and subscription exist
        self._verify_resources()

    def _verify_resources(self):
        """Verify Pub/Sub topics and subscriptions exist."""

        try:
            # Check main topic
            self.publisher_client.get_topic(request={"topic": self.topic_submissions})
            logger.info(
                f"Topic {self.settings.cloud.pubsub_topic_submissions} verified"
            )
        except exceptions.NotFound:
            logger.warning(
                f"Topic not found, creating: {self.settings.cloud.pubsub_topic_submissions}"
            )
            self.publisher_client.create_topic(request={"name": self.topic_submissions})

        try:
            # Check DLQ topic
            self.publisher_client.get_topic(request={"topic": self.topic_dlq})
            logger.info(f"DLQ Topic {self.settings.cloud.pubsub_topic_dlq} verified")
        except exceptions.NotFound:
            logger.warning(
                f"DLQ Topic not found, creating: {self.settings.cloud.pubsub_topic_dlq}"
            )
            self.publisher_client.create_topic(request={"name": self.topic_dlq})

        try:
            # Check subscription
            self.subscriber_client.get_subscription(
                request={"subscription": self.subscription_path}
            )
            logger.info(
                f"Subscription {self.settings.cloud.pubsub_subscription} verified"
            )
        except exceptions.NotFound:
            logger.warning(
                f"Subscription not found, creating: {self.settings.cloud.pubsub_subscription}"
            )
            self.subscriber_client.create_subscription(
                request={
                    "name": self.subscription_path,
                    "topic": self.topic_submissions,
                    "ack_deadline_seconds": 60,
                    "message_retention_duration": {"seconds": 604800},  # 7 days
                }
            )

    def publish_submission(
        self,
        request_id: str,
        data: Dict[str, Any],
        attributes: Optional[Dict[str, str]] = None,
    ) -> str:
        """
        Publish submission to main topic for processing.

        Args:
            request_id: Unique request identifier
            data: Submission data to process
            attributes: Additional message attributes

        Returns:
            Message ID

        Raises:
            QueueError: If publish fails
        """

        try:
            # Build message
            message_data = {
                "request_id": request_id,
                "data": data,
                "published_at": datetime.utcnow().isoformat(),
                "retry_count": 0,
            }

            message_json = json.dumps(message_data).encode("utf-8")

            # Build attributes
            msg_attributes = {
                "request_id": request_id,
                "event_type": "submission_created",
                **(attributes or {}),
            }

            # Publish
            future = self.publisher_client.publish(
                self.topic_submissions, message_json, **msg_attributes
            )

            message_id = future.result(timeout=5)

            logger.info(
                "Message published to main topic",
                request_id=request_id,
                message_id=message_id,
                data_size=len(message_json),
            )

            return message_id

        except exceptions.GoogleCloudError as e:
            raise QueueError(
                message=f"Failed to publish message: {str(e)}",
                error_code=ErrorCode.PUBSUB_PUBLISH_FAILED,
                original_exception=e,
            )

        except Exception as e:
            raise QueueError(
                message=f"Unexpected publish error: {str(e)}",
                error_code=ErrorCode.PUBSUB_PUBLISH_FAILED,
                original_exception=e,
            )

    def publish_to_dlq(
        self,
        request_id: str,
        data: Dict[str, Any],
        error_code: str,
        error_message: str,
        stage: str,
        retry_count: int = 0,
    ) -> str:
        """
        Route failed message to dead letter queue.

        Args:
            request_id: Request ID
            data: Original data that failed
            error_code: Error code
            error_message: Error message
            stage: Stage where failure occurred
            retry_count: Number of retry attempts

        Returns:
            Message ID

        Raises:
            QueueError: If publish fails
        """

        try:
            # Build DLQ message
            dlq_message = {
                "request_id": request_id,
                "original_data": data,
                "failure": {
                    "error_code": error_code,
                    "error_message": error_message,
                    "stage": stage,
                    "timestamp": datetime.utcnow().isoformat(),
                },
                "retry_count": retry_count,
                "max_retries": 5,
            }

            message_json = json.dumps(dlq_message).encode("utf-8")

            # Publish to DLQ
            future = self.publisher_client.publish(
                self.topic_dlq,
                message_json,
                request_id=request_id,
                error_code=error_code,
                stage=stage,
            )

            message_id = future.result(timeout=5)

            logger.warning(
                "Message published to DLQ",
                request_id=request_id,
                message_id=message_id,
                error_code=error_code,
                stage=stage,
                retry_count=retry_count,
            )

            return message_id

        except exceptions.GoogleCloudError as e:
            raise QueueError(
                message=f"Failed to publish to DLQ: {str(e)}",
                error_code=ErrorCode.PUBSUB_PUBLISH_FAILED,
                original_exception=e,
            )

        except Exception as e:
            raise QueueError(
                message=f"Unexpected DLQ publish error: {str(e)}",
                error_code=ErrorCode.PUBSUB_PUBLISH_FAILED,
                original_exception=e,
            )

    def pull_messages(self, max_messages: int = 10, return_immediately: bool = False):
        """
        Pull messages from subscription.

        Args:
            max_messages: Maximum messages to pull
            return_immediately: Return immediately if no messages

        Yields:
            Tuple of (message, ack_id)
        """

        try:
            # Pull messages
            response = self.subscriber_client.pull(
                request={
                    "subscription": self.subscription_path,
                    "max_messages": max_messages,
                    "return_immediately": return_immediately,
                },
                timeout=5,
            )

            for msg in response.received_messages:
                try:
                    data = json.loads(msg.message.data.decode("utf-8"))
                    yield data, msg.ack_id
                except json.JSONDecodeError as e:
                    logger.error(f"Failed to decode message: {str(e)}")
                    # Still yield so it can be ack'd and removed
                    yield None, msg.ack_id

        except exceptions.GoogleCloudError as e:
            logger.error(f"Failed to pull messages: {str(e)}")
            raise QueueError(
                message=f"Failed to pull messages: {str(e)}",
                error_code=ErrorCode.PUBSUB_CONSUME_FAILED,
                original_exception=e,
            )

    def ack_message(self, ack_id: str) -> bool:
        """
        Acknowledge message (mark as processed).

        Args:
            ack_id: Ack ID from message

        Returns:
            True if successful
        """

        try:
            self.subscriber_client.acknowledge(
                request={"subscription": self.subscription_path, "ack_ids": [ack_id]},
                timeout=5,
            )
            return True

        except Exception as e:
            logger.error(f"Failed to ack message: {str(e)}")
            return False

    def nack_message(self, ack_id: str) -> bool:
        """
        Negative acknowledge (return to queue).

        Args:
            ack_id: Ack ID from message

        Returns:
            True if successful
        """

        try:
            self.subscriber_client.modify_ack_deadline(
                request={
                    "subscription": self.subscription_path,
                    "ack_ids": [ack_id],
                    "ack_deadline_seconds": 0,  # Return immediately
                },
                timeout=5,
            )
            return True

        except Exception as e:
            logger.error(f"Failed to nack message: {str(e)}")
            return False


def get_pubsub_client() -> PubSubClient:
    """Get or create Pub/Sub client."""
    if not hasattr(get_pubsub_client, "_instance"):
        get_pubsub_client._instance = PubSubClient()
    return get_pubsub_client._instance
