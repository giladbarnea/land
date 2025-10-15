#!/usr/bin/env zsh

# # html2md <HTML_FILE / STDIN>
# Wrapper for html2text.
function html2md(){
	command html2text --no-wrap-links --ignore-images --asterisk-emphasis --unicode-snob --single-line-break --dash-unordered-list --mark-code --ignore-links "$@"
}


# # pdf2md <PDF_FILE> [docling options...]
# Convert PDF files to markdown using docling.
# Supported options:
#   --to [md|json|html|text|doctags]     Output format (default: md)
#   --output PATH                        Output directory (default: .)
#   --image-export-mode [placeholder|embedded|referenced]  How to handle images (default: referenced)
#   --table-mode [fast|accurate]         Table extraction mode (default: fast)
#   --ocr / --no-ocr                     Enable/disable OCR (default: enabled)
#   --force-ocr / --no-force-ocr         Replac	e existing text with OCR
#   --ocr-engine TEXT                    OCR engine (easyocr, tesseract, etc.)
#   --ocr-lang TEXT                      Comma-separated language codes
#   --pipeline [standard|vlm|asr]        Processing pipeline (default: standard)
#   --pdf-backend [pypdfium2|dlparse_v1|dlparse_v2|dlparse_v4]  PDF backend
#   --verbose, -v                        Increase verbosity (-v for info, -vv for debug)
#   --num-threads INTEGER                Number of threads (default: 8)
#   --device [auto|cpu|cuda|mps]         Processing device (default: auto)
#   --abort-on-error / --no-abort-on-error  Stop on first error
#   --allow-external-plugins             Enable third-party plugins
function pdf2md(){
	uvx --with=docling docling --image-export-mode=placeholder --table-mode=fast --num-threads=8 "$@" --no-ocr
}