import pdfplumber
import re
# import pytesseract
import numpy as np
from PIL import Image
import io

def remove_nested_parens(input_str):
    result = ''
    paren_level = 0
    for ch in input_str:
        if ch == '(':
            paren_level += 1
        elif ch == ')':
            if paren_level > 0:
                paren_level -= 1
        elif paren_level == 0:
            result += ch
    return result.strip()

def is_character_name(line):
    clean_line = line.strip()
    return bool(re.match(r'^[A-Z][A-Z\s]+(?:\s*\(.*?\))?$', clean_line) and
                len(clean_line.split()) <= 4 and  # Character names are usually short
                not re.match(r'^\(.*\)$', clean_line))

def is_page_number(line):
    return re.fullmatch(r"\d+\.?", line.strip())

def is_stage_direction(line):
    return re.match(r'^\s*\([^)]+\)\s*$', line.strip())

def is_narration_line(line, min_dialogue_indent=4):
    """
    Determine if a line is narration based on indentation.
    Narration lines typically have less indentation than dialogue lines.
    """
    stripped = line.strip()
    if not stripped:
        return True
    
    # Lines that are clearly not dialogue
    if (is_page_number(stripped) or 
        stripped.startswith("FADE") or 
        stripped.startswith("CUT TO") or
        stripped.startswith("INT.") or 
        stripped.startswith("EXT.") or
        stripped.startswith("BACK TO") or
        stripped.startswith("FLASHBACK") or
        stripped.endswith(":") and not ":" in stripped[:-1]):  # Scene headers
        return True
    
    # Check indentation - narration is typically flush left or minimally indented
    indent_level = len(line) - len(line.lstrip(' '))
    
    # If line has minimal indentation and contains action-like words, it's likely narration
    if indent_level < min_dialogue_indent:
        action_indicators = [
            'walks', 'runs', 'sits', 'stands', 'looks', 'turns', 'opens', 'closes',
            'enters', 'exits', 'moves', 'grabs', 'holds', 'puts', 'takes', 'places',
            'kisses', 'hugs', 'touches', 'pulls', 'pushes', 'throws', 'picks',
            'leans', 'climbs', 'drives', 'follows', 'pauses', 'stops', 'continues',
            'smiles', 'frowns', 'nods', 'shakes', 'whispers', 'shouts', 'sighs'
        ]
        
        lower_line = stripped.lower()
        if any(action in lower_line for action in action_indicators):
            return True
    
    return False

def clean_text(text):
    # Remove all nested parentheses and excess whitespace
    while True:
        new_text = re.sub(r'\([^()]*\)', '', text)
        if new_text == text:
            break
        text = new_text
    text = remove_nested_parens(text)
    text = re.sub(r'\s+', ' ', text).strip()
    return text

def extract_lines_from_page(page):
    """Extract lines from a pdfplumber page object"""
    try:
        # Try to extract text first - PDFplumber is excellent for text-based PDFs
        text = page.extract_text(layout=True, x_tolerance=1, y_tolerance=1)
        if text and text.strip():
            return text.splitlines()
        else:
            # Fall back to OCR if no text found
            return extract_lines_from_page_ocr(page)
    except:
        # If text extraction fails, use OCR
        return extract_lines_from_page_ocr(page)

def extract_lines_from_page_ocr(page):
    """Extract lines using Tesseract OCR from a pdfplumber page"""
    try:
        # Convert page to image with high resolution for better OCR
        img = page.to_image(resolution=300)
        
        # Convert to PIL Image if needed
        if hasattr(img, 'original'):
            pil_image = img.original
        else:
            pil_image = img
        
        # Use Tesseract to extract text with configuration for better accuracy
        custom_config = r'--oem 3 --psm 6 -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,!?:;()[]"\'- '
        
        # Get detailed data from Tesseract
        data = pytesseract.image_to_data(pil_image, config=custom_config, output_type=pytesseract.Output.DICT)
        
        # Group words by line based on their top coordinate
        lines_dict = {}
        for i in range(len(data['text'])):
            if int(data['conf'][i]) > 30:  # Only use words with confidence > 30
                text = data['text'][i].strip()
                if text:
                    top = data['top'][i]
                    left = data['left'][i]
                    
                    # Group words that are on the same line (within 10 pixels vertically)
                    line_key = None
                    for existing_top in lines_dict.keys():
                        if abs(top - existing_top) <= 10:
                            line_key = existing_top
                            break
                    
                    if line_key is None:
                        line_key = top
                        lines_dict[line_key] = []
                    
                    lines_dict[line_key].append((left, text))
        
        # Sort lines by their vertical position and create final text lines
        sorted_lines = []
        for top in sorted(lines_dict.keys()):
            # Sort words in each line by their horizontal position
            words = sorted(lines_dict[top], key=lambda x: x[0])
            line_text = ' '.join([word for _, word in words])
            if line_text.strip():
                sorted_lines.append(line_text.strip())
        
        return sorted_lines
        
    except Exception as e:
        print(f"OCR extraction failed: {e}")
        return []

def check_pdf_page_count(pdf_path, max_pages=20):
    """
    Check if the PDF has fewer than the specified maximum number of pages.
    
    Args:
        pdf_path (str): Path to the PDF file
        max_pages (int): Maximum number of pages to check against (default: 10)
    
    Returns:
        tuple: (bool, int) - (True if pages < max_pages, actual page count)
    """
    try:
        with pdfplumber.open(pdf_path) as pdf:
            page_count = len(pdf.pages)
            return page_count < max_pages, page_count
    except Exception as e:
        print(f"Error reading PDF: {str(e)}")
        return False, 0

def get_pdf_page_count(pdf_path):
    """
    Get the number of pages in a PDF file.

    Args:
        pdf_path (str): Path to the PDF file

    Returns:
        int: Number of pages in the PDF (0 if an error occurs)
    """
    try:
        
        with pdfplumber.open(pdf_path) as pdf:
            return len(pdf.pages)
    except Exception as e:
        print(f"Error reading PDF: {str(e)}")
        return 0

def detect_pdf_type(pdf_path, sample_pages=3):
    """Detect if PDF is text-based or image-based"""
    try:
        with pdfplumber.open(pdf_path) as pdf:
            total_pages = len(pdf.pages)
            pages_to_check = min(sample_pages, total_pages)
            text_content_found = False
            
            for page_num in range(pages_to_check):
                page = pdf.pages[page_num]
                text = page.extract_text()
                
                if text and len(text.strip()) > 20:
                    lines = text.splitlines()
                    meaningful_lines = [line.strip() for line in lines 
                                      if line.strip() and not is_page_number(line.strip())]
                    if len(meaningful_lines) > 2:
                        text_content_found = True
                        break
            
            return 'text' if text_content_found else 'image'
    except Exception as e:
        print(f"Error detecting PDF type: {e}")
        return 'image'  # Default to image if detection fails

def extract_script(pdf_path, page_numbers=None):
    """
    Extract script from PDF with optional page number filtering.
    
    Args:
        pdf_path (str): Path to the PDF file
        page_numbers (list): List of page numbers to extract (0-indexed). 
                           If None, extracts all pages except the first one.
    
    Returns:
        str: Extracted script text
    """
    pdf_type = detect_pdf_type(pdf_path)
    if pdf_type == 'image':
        return extract_script_from_image_pdf(pdf_path, page_numbers)

    with pdfplumber.open(pdf_path) as pdf:
        output_blocks = []
        
        # Calculate minimum dialogue indent by sampling the document
        min_dialogue_indent = calculate_min_dialogue_indent(pdf)
        
        # Determine which pages to process
        if page_numbers is None:
            # Default behavior: process all pages including title page
            pages_to_process = range(len(pdf.pages))
        else:
            # Filter page numbers to ensure they're valid
            pages_to_process = [p for p in page_numbers if 0 <= p < len(pdf.pages)]
            print(f"Processing pages: {pages_to_process}")
        
        for page_num in pages_to_process:
            page = pdf.pages[page_num]
            lines = extract_lines_from_page(page)
            i = 0
            while i < len(lines):
                raw_line = lines[i]
                stripped = raw_line.strip()
                
                # Skip empty lines and page numbers
                if not stripped or is_page_number(stripped):
                    i += 1
                    continue

                if is_character_name(stripped):
                    current_character = re.sub(r'\s*\([^)]*\)', '', stripped).strip().upper()
                    i += 1
                    current_dialogue = []

                    # Collect dialogue lines after character name
                    while i < len(lines):
                        next_raw_line = lines[i]
                        next_stripped = next_raw_line.strip()
                        
                        # Stop at empty, new character, or clear narration
                        if (not next_stripped or 
                            is_character_name(next_stripped) or
                            is_narration_line(next_raw_line, min_dialogue_indent)):
                            break
                        
                        # Only include lines that are clearly dialogue (properly indented and not stage directions)
                        line_indent = len(next_raw_line) - len(next_raw_line.lstrip())
                        if (line_indent >= min_dialogue_indent and 
                            not is_stage_direction(next_stripped) and
                            not is_narration_line(next_raw_line, min_dialogue_indent)):
                            
                            clean_dialogue = clean_text(next_raw_line)
                            if clean_dialogue and len(clean_dialogue) > 2:  # Avoid single characters
                                current_dialogue.append(clean_dialogue)
                        i += 1

                    if current_character and current_dialogue:
                        output_blocks.append(f"{current_character}: {' '.join(current_dialogue)}")
                    continue

                i += 1  # Not a character name; move to next line

        return '\n'.join(output_blocks)

def calculate_min_dialogue_indent(pdf, sample_pages=5):
    """
    Calculate the minimum indentation level for dialogue lines by sampling the document.
    """
    dialogue_indents = []
    
    pages_to_sample = min(sample_pages, len(pdf.pages))
    for page_num in range(1, pages_to_sample + 1):  # Skip first page
        if page_num >= len(pdf.pages):
            break
        page = pdf.pages[page_num]
        lines = extract_lines_from_page(page)
        
        found_character = False
        for i, line in enumerate(lines):
            stripped = line.strip()
            if is_character_name(stripped):
                found_character = True
                # Look at the next few lines after character name
                for j in range(i + 1, min(i + 5, len(lines))):
                    next_line = lines[j]
                    next_stripped = next_line.strip()
                    if (next_stripped and 
                        not is_character_name(next_stripped) and
                        not is_page_number(next_stripped) and
                        not is_stage_direction(next_stripped)):
                        
                        indent = len(next_line) - len(next_line.lstrip(' '))
                        if indent > 0:  # Only consider indented lines
                            dialogue_indents.append(indent)
                        break
    
    # Return the minimum common dialogue indent, default to 4 if no data
    if dialogue_indents:
        return min(dialogue_indents)
    else:
        return 4

def extract_script_from_image_pdf(pdf_path, page_numbers=None):
    """
    Extract script from image-based PDF with optional page number filtering.
    
    Args:
        pdf_path (str): Path to the PDF file
        page_numbers (list): List of page numbers to extract (0-indexed). 
                           If None, extracts all pages except the first one.
    
    Returns:
        str: Extracted script text
    """
    with pdfplumber.open(pdf_path) as pdf:
        output_blocks = []
        
        # For image PDFs, use a default minimum indent
        min_dialogue_indent = 4  # Character-based for text detection
        
        # Determine which pages to process
        if page_numbers is None:
            # Default behavior: process all pages including title page
            pages_to_process = range(len(pdf.pages))
        else:
            # Filter page numbers to ensure they're valid
            pages_to_process = [p for p in page_numbers if 0 <= p < len(pdf.pages)]
            print(f"Processing image PDF pages: {pages_to_process}")
        
        for page_num in pages_to_process:
            page = pdf.pages[page_num]
            lines = extract_lines_from_page_ocr(page)
            i = 0
            while i < len(lines):
                raw_line = lines[i]
                stripped = raw_line.strip()
                if not stripped or is_page_number(stripped):
                    i += 1
                    continue

                if is_character_name(stripped) or is_likely_character_name_ocr(stripped):
                    current_character = re.sub(r'\s*\([^)]*\)', '', stripped).strip().upper()
                    i += 1
                    current_dialogue = []

                    while i < len(lines):
                        next_raw_line = lines[i]
                        next_stripped = next_raw_line.strip()
                        
                        # Stop at empty, new character, or clear narration
                        if (not next_stripped or
                            is_character_name(next_stripped) or
                            is_likely_character_name_ocr(next_stripped) or
                            is_narration_line(next_raw_line, 4)):  # Use smaller indent for OCR
                            break

                        if not is_stage_direction(next_stripped) and not is_narration_line(next_raw_line, 4):
                            clean_dialogue = clean_text(next_raw_line)
                            if clean_dialogue and len(clean_dialogue) > 2:
                                current_dialogue.append(clean_dialogue)
                        i += 1

                    if current_character and current_dialogue:
                        output_blocks.append(f"{current_character}: {' '.join(current_dialogue)}")
                    continue
                i += 1
        
        return '\n'.join(output_blocks)

def is_likely_character_name_ocr(line):
    """Check if line is likely a character name based on OCR characteristics"""
    line = line.strip()
    if not line:
        return False
    words = line.split()
    if len(words) <= 3:
        alpha_chars = ''.join([c for c in line if c.isalpha()])
        if alpha_chars:
            uppercase_ratio = sum(1 for c in alpha_chars if c.isupper()) / len(alpha_chars)
            if uppercase_ratio > 0.7:
                return True
    return False

def get_unique_characters(script_text):
    """
    Extracts and returns a list of all unique character names from the script text.
    Assumes each dialogue line starts with CHARACTER_NAME: dialogue.
    """
    characters = set()
    for line in script_text.splitlines():
        if ':' in line:
            character = line.split(':', 1)[0].strip().upper()
            characters.add(character)
    return list(characters)

def script_without_character(script_text, character_name):
    """
    Remove all dialogue lines spoken by the given character.
    """
    character_name = character_name.strip().upper() + ":"
    filtered_lines = [
        line for line in script_text.splitlines()
        if not line.startswith(character_name)
    ]
    return "\n".join(filtered_lines)

def script_with_character(script_text, character):
    """
    Returns a string containing only the dialogue lines spoken by the specified character.
    Assumes each dialogue line starts with CHARACTER_NAME: dialogue.
    """
    character_prefix = character.strip().upper() + ":"
    selected_lines = [
        line for line in script_text.splitlines()
        if line.startswith(character_prefix)
    ]
    return "\n".join(selected_lines)

def split_dialogue_by_sentence(script_text):
    """
    Split each dialogue line after every sentence.
    """
    output_lines = []
    for line in script_text.splitlines():
        if ':' in line:
            character, dialogue = line.split(':', 1)
            character = character.strip()
            # Split dialogue into sentences using regex
            sentences = re.findall(r'[^.!?]+[.!?]+|[^.!?]+$', dialogue.strip())
            for sentence in sentences:
                sentence = sentence.strip()
                if sentence:
                    output_lines.append(f"{character}: {sentence}")
        else:
            # Non-dialogue lines (e.g., narration) are kept as is
            output_lines.append(line)
    return '\n'.join(output_lines)

# Usage examples
# if __name__ == "__main__":
#     # Example usage - replace with your PDF path
#     pdf_path = "scripts/FRIENDSHIP-BEST.pdf"  # Change this to your PDF path
    
#     try:
#         # Check page count first
#         is_small_pdf, page_count = check_pdf_page_count(pdf_path, max_pages=10)

#         # Extract all pages (default behavior - now includes title page)
#         script_text = extract_script(pdf_path, page_numbers=[1,5,8])
        
#         # Save to file
#         output_filename = "dialogue_only_script.txt"
#         with open(output_filename, "w", encoding="utf-8") as f:
#             f.write(script_text)
        
#         print(f"Script extraction completed! Output saved to {output_filename}")
#         print(f"Extracted {len(script_text.splitlines())} lines of dialogue.")
        
#         # Print first few lines for debugging
#         print("\nFirst few lines of output:")
#         for i, line in enumerate(script_text.splitlines()[:10]):
#             print(f"{i+1}: {line}")
        
#     except Exception as e:
#         print(f"Error processing PDF: {str(e)}")