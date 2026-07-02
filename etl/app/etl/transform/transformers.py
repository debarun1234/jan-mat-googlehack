"""
Text transformation module (CP-5 checkpoint).
Cleans and normalizes text before AI processing.
"""

import re
import logging
from typing import Dict, Any, Optional
from datetime import datetime

from app.config.settings import get_settings
from app.utils.errors import TransformationError, ErrorCode


logger = logging.getLogger(__name__)


class TextCleaner:
    """Text cleaning and normalization."""
    
    def __init__(self):
        self.settings = get_settings()
    
    def remove_extra_whitespace(self, text: str) -> str:
        """Remove extra whitespace and normalize line breaks."""
        # Replace multiple spaces with single space
        text = re.sub(r' +', ' ', text)
        # Replace multiple newlines with double newline
        text = re.sub(r'\n\n+', '\n\n', text)
        # Strip leading/trailing whitespace
        text = text.strip()
        return text
    
    def remove_special_characters(
        self,
        text: str,
        keep_punctuation: bool = True
    ) -> str:
        """Remove unwanted special characters."""
        
        if keep_punctuation:
            # Keep basic punctuation, remove control characters
            text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '', text)
        else:
            # Remove all non-alphanumeric except spaces
            text = re.sub(r'[^a-zA-Z0-9\s\.\,\!\?\-\(\)]', '', text)
        
        return text
    
    def remove_urls(self, text: str) -> str:
        """Remove URLs and links."""
        # Remove http(s) URLs
        text = re.sub(r'https?://[^\s]+', '', text)
        # Remove www URLs
        text = re.sub(r'www\.[^\s]+', '', text)
        return text
    
    def remove_emails(self, text: str) -> str:
        """Remove email addresses."""
        text = re.sub(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b', '', text)
        return text
    
    def remove_phone_numbers(self, text: str) -> str:
        """Remove phone numbers."""
        # Indian phone number formats
        text = re.sub(r'\+91[\s]?[0-9]{10}', '', text)
        text = re.sub(r'\b[0-9]{10}\b', '', text)  # Might be too aggressive
        text = re.sub(r'\([0-9]{3,4}\)\s?[0-9]{3,4}\s?[0-9]{4}', '', text)
        return text
    
    def normalize_indic_text(self, text: str) -> str:
        """Normalize Indic language text."""
        
        # Normalize zero-width characters common in Indic text
        text = text.replace('\u200b', '')  # Zero-width space
        text = text.replace('\u200c', '')  # Zero-width non-joiner
        text = text.replace('\u200d', '')  # Zero-width joiner
        text = text.replace('\ufeff', '')  # Zero-width no-break space
        
        return text
    
    def normalize_unicode(self, text: str) -> str:
        """Normalize Unicode to NFC form."""
        import unicodedata
        return unicodedata.normalize('NFC', text)
    
    def expand_contractions(self, text: str) -> str:
        """Expand English contractions."""
        
        contractions_dict = {
            "don't": "do not",
            "doesn't": "does not",
            "didn't": "did not",
            "can't": "cannot",
            "won't": "will not",
            "isn't": "is not",
            "aren't": "are not",
            "wasn't": "was not",
            "weren't": "were not",
            "haven't": "have not",
            "hasn't": "has not",
            "hadn't": "had not",
            "shouldn't": "should not",
            "couldn't": "could not",
            "i'm": "i am",
            "you're": "you are",
            "he's": "he is",
            "she's": "she is",
            "it's": "it is",
            "we're": "we are",
            "they're": "they are",
        }
        
        for contraction, expansion in contractions_dict.items():
            text = re.sub(
                rf'\b{re.escape(contraction)}\b',
                expansion,
                text,
                flags=re.IGNORECASE
            )
        
        return text
    
    def clean_text(
        self,
        text: str,
        request_id: Optional[str] = None,
        remove_urls: bool = True,
        remove_emails: bool = True,
        remove_phones: bool = False,
        expand_contractions: bool = True
    ) -> str:
        """
        Apply all cleaning transformations.
        
        Args:
            text: Raw text to clean
            request_id: Request ID for logging
            remove_urls: Remove URL links
            remove_emails: Remove email addresses
            remove_phones: Remove phone numbers
            expand_contractions: Expand English contractions
        
        Returns:
            Cleaned text
        """
        
        try:
            original_length = len(text)
            
            # Apply transformations in sequence
            text = self.normalize_unicode(text)
            text = self.normalize_indic_text(text)
            text = self.remove_special_characters(text, keep_punctuation=True)
            
            if remove_urls:
                text = self.remove_urls(text)
            
            if remove_emails:
                text = self.remove_emails(text)
            
            if remove_phones:
                text = self.remove_phone_numbers(text)
            
            text = self.remove_extra_whitespace(text)
            
            if expand_contractions:
                text = self.expand_contractions(text)
            
            final_length = len(text)
            
            logger.info(
                f"Text cleaning completed",
                request_id=request_id,
                original_length=original_length,
                final_length=final_length,
                reduction_percent=round((1 - final_length / original_length) * 100, 2) if original_length > 0 else 0
            )
            
            return text
        
        except Exception as e:
            raise TransformationError(
                message=f"Text cleaning failed: {str(e)}",
                error_code=ErrorCode.TRANSFORMATION_FAILED,
                request_id=request_id,
                original_exception=e
            )


class TextNormalizer:
    """Text normalization for consistent processing."""
    
    def __init__(self):
        self.settings = get_settings()
    
    def normalize_for_ai(self, text: str) -> str:
        """Normalize text optimally for AI processing."""
        
        # Preserve formatting but ensure consistency
        lines = text.split('\n')
        normalized_lines = []
        
        for line in lines:
            # Strip each line
            stripped = line.strip()
            if stripped:  # Keep non-empty lines
                normalized_lines.append(stripped)
        
        # Join with single newlines
        return '\n'.join(normalized_lines)
    
    def extract_sentences(self, text: str) -> list:
        """Extract sentences from text."""
        
        # Simple sentence splitter
        # Handles . ! ? as sentence endings
        sentences = re.split(r'(?<=[.!?])\s+', text)
        return [s.strip() for s in sentences if s.strip()]
    
    def extract_key_phrases(self, text: str, max_phrases: int = 10) -> list:
        """Extract potential key phrases."""
        
        # Simple approach: get longest noun phrases
        # In production, use NER or TF-IDF
        words = text.split()
        
        # Return longest consecutive phrases
        phrases = []
        for i in range(len(words) - 2):
            phrase = ' '.join(words[i:i+3])
            if len(phrase) > 10 and phrase not in phrases:
                phrases.append(phrase)
        
        return phrases[:max_phrases]


class DataTransformer:
    """Transform extracted data into structured format."""
    
    def __init__(self):
        self.settings = get_settings()
        self.cleaner = TextCleaner()
        self.normalizer = TextNormalizer()
    
    def transform_extraction_result(
        self,
        extraction_result: Dict[str, Any],
        request_id: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Transform extraction result for AI processing (CP-5).
        
        Args:
            extraction_result: Result from extractor
            request_id: Request ID for logging
        
        Returns:
            Transformed data ready for AI
        
        Raises:
            TransformationError: If transformation fails
        """
        
        try:
            raw_text = extraction_result.get("extracted_text", "")
            
            # Clean the text
            cleaned_text = self.cleaner.clean_text(
                raw_text,
                request_id=request_id
            )
            
            # Normalize for AI
            normalized_text = self.normalizer.normalize_for_ai(cleaned_text)
            
            # Validate cleaned text length
            if len(normalized_text) < self.settings.processing.min_text_length:
                raise TransformationError(
                    message="Text too short after cleaning",
                    error_code=ErrorCode.TRANSFORMATION_FAILED,
                    request_id=request_id,
                    details={
                        "length": len(normalized_text),
                        "minimum": self.settings.processing.min_text_length
                    }
                )
            
            if len(normalized_text) > self.settings.processing.max_text_length:
                # Truncate if too long
                normalized_text = normalized_text[:self.settings.processing.max_text_length]
                logger.warning(
                    f"Text truncated to max length",
                    request_id=request_id,
                    length=len(normalized_text)
                )
            
            # Extract metadata
            sentences = self.normalizer.extract_sentences(normalized_text)
            key_phrases = self.normalizer.extract_key_phrases(normalized_text)
            
            transformed = {
                "raw_text": raw_text,
                "cleaned_text": cleaned_text,
                "normalized_text": normalized_text,
                "confidence": extraction_result.get("confidence", 0.0),
                "language": extraction_result.get("language", "unknown"),
                "extraction_method": extraction_result.get("extraction_method", "unknown"),
                "sentence_count": len(sentences),
                "word_count": len(normalized_text.split()),
                "character_count": len(normalized_text),
                "key_phrases": key_phrases,
                "metadata": {
                    **extraction_result.get("metadata", {}),
                    "transformation_timestamp": datetime.utcnow().isoformat(),
                    "cleaned_at_stage": "CP-5"
                }
            }
            
            logger.info(
                f"Data transformation completed",
                request_id=request_id,
                word_count=transformed["word_count"],
                sentence_count=transformed["sentence_count"]
            )
            
            return transformed
        
        except TransformationError:
            raise
        
        except Exception as e:
            raise TransformationError(
                message=f"Data transformation failed: {str(e)}",
                error_code=ErrorCode.TRANSFORMATION_FAILED,
                request_id=request_id,
                original_exception=e
            )


def get_text_cleaner() -> TextCleaner:
    """Get text cleaner instance."""
    if not hasattr(get_text_cleaner, "_instance"):
        get_text_cleaner._instance = TextCleaner()
    return get_text_cleaner._instance


def get_data_transformer() -> DataTransformer:
    """Get data transformer instance."""
    if not hasattr(get_data_transformer, "_instance"):
        get_data_transformer._instance = DataTransformer()
    return get_data_transformer._instance
