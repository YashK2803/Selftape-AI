import fitz  # PyMuPDF
import re
from paddleocr import PaddleOCR
import numpy as np
from PIL import Image
import io

ocr = PaddleOCR(lang='en', enable_mkldnn=False)

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
    text = page.get_text("text", sort=True).strip()
    if text:
        return text.splitlines()
    else:
        pix = page.get_pixmap()
        img = Image.open(io.BytesIO(pix.tobytes()))
        result = ocr.ocr(np.array(img))
        return [line[1][0] for line in result[0]] if result else []

def detect_pdf_type(pdf_path, sample_pages=3):
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    pages_to_check = min(sample_pages, total_pages)
    text_content_found = False
    for page_num in range(pages_to_check):
        page = doc[page_num]
        text = page.get_text("text", sort=True).strip()
        if text and len(text) > 20:
            lines = text.splitlines()
            meaningful_lines = [line.strip() for line in lines if line.strip() and not is_page_number(line.strip())]
            if len(meaningful_lines) > 2:
                text_content_found = True
                break
    doc.close()
    return 'text' if text_content_found else 'image'

def extract_script(pdf_path):
    pdf_type = detect_pdf_type(pdf_path)
    if pdf_type == 'image':
        return extract_script_from_image_pdf(pdf_path)

    doc = fitz.open(pdf_path)
    output_blocks = []
    
    # Calculate minimum dialogue indent by sampling the document
    min_dialogue_indent = calculate_min_dialogue_indent(doc)
    
    for page_num, page in enumerate(doc):
        if page_num == 0:
            continue  # Skip title page
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

    doc.close()
    return '\n'.join(output_blocks)

def calculate_min_dialogue_indent(doc, sample_pages=5):
    """
    Calculate the minimum indentation level for dialogue lines by sampling the document.
    """
    dialogue_indents = []
    
    pages_to_sample = min(sample_pages, len(doc))
    for page_num in range(1, pages_to_sample + 1):  # Skip first page
        if page_num >= len(doc):
            break
        page = doc[page_num]
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

def extract_lines_from_image_page(page):
    pix = page.get_pixmap(matrix=fitz.Matrix(3, 3))
    img = Image.open(io.BytesIO(pix.tobytes()))
    if img.mode != 'RGB':
        img = img.convert('RGB')
    result = ocr.ocr(np.array(img))
    if result and result[0]:
        ocr_results = []
        for line in result[0]:
            bbox = line[0]
            text_info = line[1]
            text = text_info[0]
            confidence = text_info[1]
            if confidence > 0.5:
                y_coord = (bbox[0][1] + bbox[2][1]) / 2
                x_coord = (bbox[0][0] + bbox[2][0]) / 2
                ocr_results.append((y_coord, x_coord, text))
        ocr_results.sort(key=lambda x: (x[0], x[1]))
        grouped_lines = []
        current_group = []
        current_y = None
        y_threshold = 10
        for y_coord, x_coord, text in ocr_results:
            if current_y is None or abs(y_coord - current_y) <= y_threshold:
                current_group.append((x_coord, text))
                current_y = y_coord if current_y is None else current_y
            else:
                if current_group:
                    current_group.sort(key=lambda x: x[0])
                    line_text = ' '.join([text for _, text in current_group])
                    grouped_lines.append(line_text)
                current_group = [(x_coord, text)]
                current_y = y_coord
        if current_group:
            current_group.sort(key=lambda x: x[0])
            line_text = ' '.join([text for _, text in current_group])
            grouped_lines.append(line_text)
        return grouped_lines
    return []

def extract_script_from_image_pdf(pdf_path):
    doc = fitz.open(pdf_path)
    output_blocks = []
    
    # For image PDFs, use a default minimum indent
    min_dialogue_indent = 20  # Pixels for image-based detection
    
    for page_num, page in enumerate(doc):
        if page_num == 0:
            continue
        lines = extract_lines_from_image_page(page)
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
    doc.close()
    return '\n'.join(output_blocks)

def is_likely_character_name_ocr(line):
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

# Usage
# if __name__ == "__main__":
#     # Example usage - replace with your PDF path
#     pdf_path = "scripts/24hourcustody.pdf"  # Change this to your PDF path
    
#     try:
#         script_text = extract_script(pdf_path)
        
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