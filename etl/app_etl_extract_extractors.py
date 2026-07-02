"""
Data extraction module (CP-3 checkpoint).
Extracts text from images (OCR), audio (STT), PDFs, and text inputs.
"""

import logging
from typing import Dict, Any, Optional
from abc import ABC, abstractmethod
from datetime import datetime

from app.config.settings import get_settings
from app.utils.errors import ExtractionError, ErrorCode


logger = logging.getLogger(__name__)


class BaseExtractor(ABC):
    """Base class for all extractors."""
    
    def __init__(self):
        self.settings = get_settings()
    
    @abstractmethod
    def extract(
        self,
        content: Any,
        request_id: str,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Extract text from content.
        
        Returns:
            Dict with extracted_text, confidence, language, etc.
        """
        pass


class TextExtractor(BaseExtractor):
    """Extract from raw text input."""
    
    def extract(
        self,
        content: str,
        request_id: str,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Extract from raw text (simple pass-through).
        
        Args:
            content: Raw text string
            request_id: Request ID for logging
        
        Returns:
            Extraction result
        """
        
        try:
            if not isinstance(content, str):
                raise ExtractionError(
                    message="Content must be string for text extraction",
                    error_code=ErrorCode.EXTRACTION_FAILED,
                    request_id=request_id
                )
            
            text = content.strip()
            
            if len(text) == 0:
                raise ExtractionError(
                    message="Text content is empty",
                    error_code=ErrorCode.EXTRACTION_FAILED,
                    request_id=request_id
                )
            
            # Language detection
            language = kwargs.get("language", "en")
            
            logger.info(
                f"Text extracted successfully",
                request_id=request_id,
                text_length=len(text),
                language=language
            )
            
            return {
                "extracted_text": text,
                "confidence": 1.0,
                "language": language,
                "extraction_method": "text_input",
                "metadata": {
                    "original_length": len(content),
                    "trimmed_length": len(text),
                    "extraction_timestamp": datetime.utcnow().isoformat()
                }
            }
        
        except ExtractionError:
            raise
        
        except Exception as e:
            raise ExtractionError(
                message=f"Text extraction failed: {str(e)}",
                error_code=ErrorCode.EXTRACTION_FAILED,
                request_id=request_id,
                original_exception=e
            )


class ImageExtractor(BaseExtractor):
    """Extract text from images using OCR."""
    
    def __init__(self):
        super().__init__()
        self._init_vision_client()
    
    def _init_vision_client(self):
        """Initialize Google Cloud Vision API client."""
        
        try:
            from google.cloud import vision
            self.vision_client = vision.ImageAnnotatorClient()
            logger.info("Vision API client initialized")
        
        except Exception as e:
            logger.error(f"Failed to initialize Vision API: {str(e)}")
            self.vision_client = None
    
    def extract(
        self,
        content: bytes,
        request_id: str,
        gcs_uri: Optional[str] = None,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Extract text from image using OCR.
        
        Args:
            content: Image bytes (if gcs_uri not provided)
            request_id: Request ID for logging
            gcs_uri: GCS URI to image (preferred)
        
        Returns:
            Extraction result with detected text
        """
        
        if not self.settings.processing.enable_ocr:
            raise ExtractionError(
                message="OCR is not enabled",
                error_code=ErrorCode.OCR_FAILED,
                request_id=request_id
            )
        
        if not self.vision_client:
            raise ExtractionError(
                message="Vision API client not initialized",
                error_code=ErrorCode.OCR_FAILED,
                request_id=request_id
            )
        
        try:
            from google.cloud import vision
            
            # Create image object
            if gcs_uri:
                image = vision.Image(source=vision.ImageSource(gcs_image_uri=gcs_uri))
            else:
                image = vision.Image(content=content)
            
            # Perform OCR
            request = vision.AnnotateImageRequest(
                image=image,
                features=[
                    vision.Feature(type_=vision.Feature.Type.TEXT_DETECTION),
                    vision.Feature(type_=vision.Feature.Type.DOCUMENT_TEXT_DETECTION),
                ]
            )
            
            response = self.vision_client.annotate_image(request)
            
            if response.error.message:
                raise ExtractionError(
                    message=f"Vision API error: {response.error.message}",
                    error_code=ErrorCode.OCR_FAILED,
                    request_id=request_id
                )
            
            # Extract text
            extracted_text = ""
            confidence = 0.0
            
            # Use document text detection for better results
            if response.document_text_annotation:
                extracted_text = response.document_text_annotation.text
                confidence = 0.9  # Document text detection is highly accurate
            
            elif response.text_annotations:
                # Fallback to basic text detection
                extracted_text = response.text_annotations[0].description
                confidence = response.text_annotations[0].confidence or 0.8
            
            if not extracted_text or len(extracted_text.strip()) == 0:
                logger.warning(f"No text detected in image (request_id={request_id})")
                extracted_text = "[No text detected in image]"
                confidence = 0.5
            
            logger.info(
                f"OCR extraction completed",
                request_id=request_id,
                text_length=len(extracted_text),
                confidence=confidence
            )
            
            return {
                "extracted_text": extracted_text.strip(),
                "confidence": confidence,
                "language": "unknown",  # Vision API doesn't always detect language
                "extraction_method": "ocr_vision_api",
                "metadata": {
                    "text_annotations_count": len(response.text_annotations),
                    "extraction_timestamp": datetime.utcnow().isoformat()
                }
            }
        
        except ExtractionError:
            raise
        
        except Exception as e:
            raise ExtractionError(
                message=f"Image extraction failed: {str(e)}",
                error_code=ErrorCode.OCR_FAILED,
                request_id=request_id,
                original_exception=e
            )


class AudioExtractor(BaseExtractor):
    """Extract text from audio using Speech-to-Text."""
    
    def __init__(self):
        super().__init__()
        self._init_speech_client()
    
    def _init_speech_client(self):
        """Initialize Google Cloud Speech-to-Text client."""
        
        try:
            from google.cloud import speech_v1
            self.speech_client = speech_v1.SpeechClient()
            logger.info("Speech-to-Text client initialized")
        
        except Exception as e:
            logger.error(f"Failed to initialize Speech-to-Text: {str(e)}")
            self.speech_client = None
    
    def extract(
        self,
        content: bytes,
        request_id: str,
        gcs_uri: Optional[str] = None,
        language_code: str = "en-US",
        **kwargs
    ) -> Dict[str, Any]:
        """
        Extract text from audio using Speech-to-Text.
        
        Args:
            content: Audio bytes (if gcs_uri not provided)
            request_id: Request ID for logging
            gcs_uri: GCS URI to audio file
            language_code: BCP-47 language code
        
        Returns:
            Extraction result with transcribed text
        """
        
        if not self.settings.processing.enable_stt:
            raise ExtractionError(
                message="Speech-to-Text is not enabled",
                error_code=ErrorCode.STT_FAILED,
                request_id=request_id
            )
        
        if not self.speech_client:
            raise ExtractionError(
                message="Speech-to-Text client not initialized",
                error_code=ErrorCode.STT_FAILED,
                request_id=request_id
            )
        
        try:
            from google.cloud import speech_v1
            
            # Detect encoding from audio
            audio = speech_v1.RecognitionAudio(
                uri=gcs_uri if gcs_uri else None,
                content=content if not gcs_uri else None
            )
            
            config = speech_v1.RecognitionConfig(
                encoding=speech_v1.RecognitionConfig.AudioEncoding.AUTO,
                sample_rate_hertz=16000,
                language_code=language_code,
                enable_automatic_punctuation=True,
                model="latest_long",  # Long-form audio
            )
            
            request = speech_v1.RecognizeRequest(
                config=config,
                audio=audio
            )
            
            response = self.speech_client.recognize(request=request)
            
            # Extract transcription
            extracted_text = ""
            confidence = 0.0
            
            for result in response.results:
                if result.alternatives:
                    # Get highest confidence alternative
                    best_alternative = result.alternatives[0]
                    extracted_text += best_alternative.transcript + " "
                    confidence = max(confidence, best_alternative.confidence)
            
            extracted_text = extracted_text.strip()
            
            if not extracted_text:
                logger.warning(f"No speech detected in audio (request_id={request_id})")
                extracted_text = "[No speech detected]"
                confidence = 0.0
            
            # Map language code to language name
            language = language_code.split("-")[0]  # en-US → en
            
            logger.info(
                f"STT extraction completed",
                request_id=request_id,
                text_length=len(extracted_text),
                confidence=confidence,
                language=language
            )
            
            return {
                "extracted_text": extracted_text,
                "confidence": confidence,
                "language": language,
                "extraction_method": "speech_to_text",
                "metadata": {
                    "language_code": language_code,
                    "result_count": len(response.results),
                    "extraction_timestamp": datetime.utcnow().isoformat()
                }
            }
        
        except ExtractionError:
            raise
        
        except Exception as e:
            raise ExtractionError(
                message=f"Audio extraction failed: {str(e)}",
                error_code=ErrorCode.STT_FAILED,
                request_id=request_id,
                original_exception=e
            )


class PDFExtractor(BaseExtractor):
    """Extract text from PDF documents."""
    
    def __init__(self):
        super().__init__()
        self._init_pdf_client()
    
    def _init_pdf_client(self):
        """Initialize PDF processing library."""
        
        try:
            import PyPDF2
            self.pdf_library = "PyPDF2"
            logger.info("PyPDF2 available for PDF extraction")
        
        except ImportError:
            try:
                import pdfplumber
                self.pdf_library = "pdfplumber"
                logger.info("pdfplumber available for PDF extraction")
            except ImportError:
                logger.warning("No PDF library available")
                self.pdf_library = None
    
    def extract(
        self,
        content: bytes,
        request_id: str,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Extract text from PDF.
        
        Args:
            content: PDF file bytes
            request_id: Request ID for logging
        
        Returns:
            Extraction result with text from PDF
        """
        
        if not self.pdf_library:
            raise ExtractionError(
                message="PDF extraction library not available",
                error_code=ErrorCode.PDF_PARSE_FAILED,
                request_id=request_id
            )
        
        try:
            extracted_text = ""
            page_count = 0
            
            if self.pdf_library == "PyPDF2":
                extracted_text = self._extract_pypdf2(content, request_id)
            
            elif self.pdf_library == "pdfplumber":
                extracted_text = self._extract_pdfplumber(content, request_id)
            
            if not extracted_text or len(extracted_text.strip()) == 0:
                logger.warning(f"No text extracted from PDF (request_id={request_id})")
                extracted_text = "[PDF contains no extractable text]"
                confidence = 0.3
            else:
                confidence = 0.85
            
            logger.info(
                f"PDF extraction completed",
                request_id=request_id,
                text_length=len(extracted_text),
                confidence=confidence
            )
            
            return {
                "extracted_text": extracted_text.strip(),
                "confidence": confidence,
                "language": "unknown",
                "extraction_method": f"pdf_{self.pdf_library}",
                "metadata": {
                    "extraction_timestamp": datetime.utcnow().isoformat()
                }
            }
        
        except ExtractionError:
            raise
        
        except Exception as e:
            raise ExtractionError(
                message=f"PDF extraction failed: {str(e)}",
                error_code=ErrorCode.PDF_PARSE_FAILED,
                request_id=request_id,
                original_exception=e
            )
    
    def _extract_pypdf2(self, content: bytes, request_id: str) -> str:
        """Extract using PyPDF2."""
        
        try:
            from io import BytesIO
            import PyPDF2
            
            pdf_reader = PyPDF2.PdfReader(BytesIO(content))
            extracted_text = ""
            
            for page_num, page in enumerate(pdf_reader.pages):
                try:
                    extracted_text += page.extract_text() + "\n"
                except Exception as e:
                    logger.warning(f"Failed to extract page {page_num}: {str(e)}")
            
            return extracted_text
        
        except Exception as e:
            raise ExtractionError(
                message=f"PyPDF2 extraction error: {str(e)}",
                error_code=ErrorCode.PDF_PARSE_FAILED,
                request_id=request_id,
                original_exception=e
            )
    
    def _extract_pdfplumber(self, content: bytes, request_id: str) -> str:
        """Extract using pdfplumber."""
        
        try:
            from io import BytesIO
            import pdfplumber
            
            extracted_text = ""
            
            with pdfplumber.open(BytesIO(content)) as pdf:
                for page_num, page in enumerate(pdf.pages):
                    try:
                        extracted_text += page.extract_text() or "" + "\n"
                    except Exception as e:
                        logger.warning(f"Failed to extract page {page_num}: {str(e)}")
            
            return extracted_text
        
        except Exception as e:
            raise ExtractionError(
                message=f"pdfplumber extraction error: {str(e)}",
                error_code=ErrorCode.PDF_PARSE_FAILED,
                request_id=request_id,
                original_exception=e
            )


class ExtractorFactory:
    """Factory for creating appropriate extractor."""
    
    @staticmethod
    def get_extractor(input_type: str) -> BaseExtractor:
        """
        Get extractor for input type.
        
        Args:
            input_type: Type of input (text, image, audio, pdf)
        
        Returns:
            Appropriate extractor instance
        """
        
        extractors = {
            "text": TextExtractor(),
            "image": ImageExtractor(),
            "audio": AudioExtractor(),
            "pdf": PDFExtractor(),
        }
        
        if input_type not in extractors:
            raise ExtractionError(
                message=f"No extractor for input type: {input_type}",
                error_code=ErrorCode.EXTRACTION_FAILED
            )
        
        return extractors[input_type]


def get_extractor(input_type: str) -> BaseExtractor:
    """Get extractor for input type."""
    return ExtractorFactory.get_extractor(input_type)
