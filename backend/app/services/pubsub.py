"""
Pub/Sub publisher service — async event pipeline.

Topics:
  grievance-submitted   → triggers async processing (clustering, scoring)
  processing-complete   → triggers Evidence Log generation
  priority-updated      → triggers MP dashboard refresh
"""

import json
import structlog
from google.cloud import pubsub_v1
from tenacity import retry, stop_after_attempt, wait_exponential

from app.config import get_settings

log = structlog.get_logger()


class PubSubService:
    def __init__(self):
        settings = get_settings()
        self._project_id = settings.gcp_project_id
        self._topics = {
            "grievance_submitted": settings.pubsub_topic_grievance_submitted,
            "processing_complete": settings.pubsub_topic_processing_complete,
            "priority_updated": settings.pubsub_topic_priority_updated,
        }
        self._publisher: pubsub_v1.PublisherClient | None = None

    def _get_publisher(self) -> pubsub_v1.PublisherClient:
        if self._publisher is None:
            self._publisher = pubsub_v1.PublisherClient()
        return self._publisher

    def _topic_path(self, topic_name: str) -> str:
        return f"projects/{self._project_id}/topics/{topic_name}"

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=6),
        reraise=True,
    )
    async def publish(
        self,
        topic_key: str,
        data: dict,
        attributes: dict[str, str] | None = None,
    ) -> str:
        """
        Publish a message to a Pub/Sub topic.

        Args:
            topic_key: One of 'grievance_submitted', 'processing_complete', 'priority_updated'
            data: JSON-serialisable dict
            attributes: Optional string key-value message attributes

        Returns:
            message_id
        """
        topic_name = self._topics[topic_key]
        topic_path = self._topic_path(topic_name)

        publisher = self._get_publisher()
        payload = json.dumps(data, default=str).encode("utf-8")

        future = publisher.publish(
            topic_path,
            data=payload,
            **(attributes or {}),
        )
        message_id = future.result(timeout=10)

        log.info("pubsub_published", topic=topic_name, message_id=message_id)
        return message_id

    async def publish_grievance_submitted(
        self,
        submission_id: str,
        constituency_id: str,
        input_type: str,
    ) -> str:
        return await self.publish(
            "grievance_submitted",
            {
                "submission_id": submission_id,
                "constituency_id": constituency_id,
                "input_type": input_type,
            },
            attributes={"input_type": input_type, "constituency_id": constituency_id},
        )

    async def publish_processing_complete(
        self,
        submission_id: str,
        constituency_id: str,
    ) -> str:
        return await self.publish(
            "processing_complete",
            {
                "submission_id": submission_id,
                "constituency_id": constituency_id,
            },
        )

    async def publish_priority_updated(
        self,
        constituency_id: str,
        top_rank: int = 1,
    ) -> str:
        return await self.publish(
            "priority_updated",
            {
                "constituency_id": constituency_id,
                "top_rank": top_rank,
            },
        )


_pubsub_service: PubSubService | None = None


def get_pubsub_service() -> PubSubService:
    global _pubsub_service
    if _pubsub_service is None:
        _pubsub_service = PubSubService()
    return _pubsub_service
