import argparse
import json
import xml.etree.ElementTree as ET
import html
import os
import re

def seconds_to_timestamp(seconds):
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}"

def sanitize_filename(title):
    sanitized = re.sub(r'[^\w\s-]', '', title.lower())
    sanitized = re.sub(r'[-\s]+', '-', sanitized)
    return sanitized.strip('-')

def parse_chapter(chapter_item) -> tuple[float | None, str | None]:
    try:
        # Handle dictionary format (original expected format)
        if isinstance(chapter_item, dict):
            start_time = chapter_item.get('start_time')
            title = chapter_item.get('title')
            if start_time is not None and title is not None:
                return float(start_time), title
            return None, None
        
        # Handle string format: "XX. [HH:MM:SS-HH:MM:SS] Title"
        elif isinstance(chapter_item, str):
            # Extract using regex: "XX. [HH:MM:SS-HH:MM:SS] Title"
            import re
            pattern = r'^\d+\.\s*\[(\d{2}:\d{2}:\d{2})-\d{2}:\d{2}:\d{2}\]\s*(.+)$'
            match = re.match(pattern, chapter_item)
            if match:
                time_str, title = match.groups()
                # Convert time string to seconds
                time_parts = time_str.split(':')
                start_seconds = int(time_parts[0]) * 3600 + int(time_parts[1]) * 60 + int(time_parts[2])
                return float(start_seconds), title.strip()
            return None, None
        
        return None, None
    except (ValueError, AttributeError):
        return None, None

def add_chapters_to_xml_tree(tree: ET.ElementTree, video_info: dict) -> ET.ElementTree:
    root = tree.getroot()
    
    # Prepare chapters
    chapters = []
    for ch_dict in video_info.get('chapters', []):
        start_sec, title = parse_chapter(ch_dict)
        if start_sec is not None and title is not None:
            chapters.append({'start': start_sec, 'title': title})

    if not chapters:
        # Create a single chapter from the entire video
        chapters.append(
            {"start": 0, "title": video_info.get("title", "Video Transcript")}
        )
        
    # Group subtitles by chapters
    original_texts = list(root)
    chapter_elements = []
    
    for i, chapter in enumerate(chapters):
        chapter_start = chapter['start']
        chapter_end = chapters[i + 1]['start'] if i + 1 < len(chapters) else float('inf')
        
        # Create chapter element
        chapter_elem = ET.Element('chapter', {
            'title': chapter['title'],
            'start': str(chapter_start),
            'end': str(chapter_end) if chapter_end != float('inf') else 'end'
        })
        
        # Find all text elements that belong to this chapter
        for text_elem in original_texts:
            text_start_time = float(text_elem.get('start', 0))
            if chapter_start <= text_start_time < chapter_end:
                chapter_elem.append(text_elem)
        
        chapter_elements.append(chapter_elem)

    # Update XML tree
    root.clear()
    root.extend(chapter_elements)
    
    return tree

def xml_tree_to_markdown(tree: ET.ElementTree, video_info: dict, output_file: str, split_chapters: bool):
    root = tree.getroot()
    video_title = video_info.get('title', 'Video Transcript')
    chapters = root.findall('chapter')
    
    if split_chapters:
        output_dir = os.path.splitext(output_file)[0] if output_file != '-' else 'chapters'
        os.makedirs(output_dir, exist_ok=True)
        
        for i, chapter in enumerate(chapters):
            title = chapter.get('title', f'Chapter {i+1}')
            start_time = float(chapter.get('start', 0))
            timestamp = seconds_to_timestamp(start_time)
            
            sanitized_title = sanitize_filename(title)
            chapter_filename = f"{i:02d}-{sanitized_title}.md"
            chapter_path = os.path.join(output_dir, chapter_filename)
            
            chapter_content = []
            chapter_content.append(f"# {video_title}\n\n")
            
            chapter_content.append(f"## {i:02d}. {title} ({timestamp})\n\n")
            
            text_elements = chapter.findall('text')
            for text_elem in text_elements:
                text_content = text_elem.text
                if text_content:
                    decoded_text = html.unescape(text_content.strip())
                    chapter_content.append(f"{decoded_text} ")
            
            chapter_content.append("\n")
            
            try:
                with open(chapter_path, 'w', encoding='utf-8') as f:
                    f.write("".join(chapter_content))
            except IOError as e:
                print(f"Error writing chapter file {chapter_path}: {e}")
                return
        
        print(f"Successfully created {len(chapters)} chapter files in '{output_dir}/' directory.")
    else:
        markdown_content = []
        
        markdown_content.append(f"# {video_title}\n")
        
        for i, chapter in enumerate(chapters):
            title = chapter.get('title', f'Chapter {i+1}')
            start_time = float(chapter.get('start', 0))
            timestamp = seconds_to_timestamp(start_time)
            
            markdown_content.append(f"## {i:02d}. {title} ({timestamp})\n")
            
            text_elements = chapter.findall('text')
            for text_elem in text_elements:
                text_content = text_elem.text
                if text_content:
                    decoded_text = html.unescape(text_content.strip())
                    markdown_content.append(f"{decoded_text} ")
            
            markdown_content.append("\n\n")
        
        full_content = "".join(markdown_content)
        
        try:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(full_content)
            print(f"Successfully created '{output_file}' with {len(chapters)} chapters.")
        except IOError as e:
            print(f"Error writing to output file {output_file}: {e}")

def process_xml_to_markdown(xml_file: str, info_file: str, output_file: str, split_chapters: bool):
    # Load video info
    try:
        with open(info_file, 'r', encoding='utf-8') as f:
            video_info = json.load(f)
    except FileNotFoundError:
        print(f"Error: JSON file not found at {info_file}")
        return
    except json.JSONDecodeError as e:
        print(f"Error: Could not parse JSON file at {info_file}: {e}")
        return

    # Parse XML
    try:
        tree = ET.parse(xml_file)
    except (FileNotFoundError, ET.ParseError) as e:
        print(f"Error: Could not read or parse XML file at {xml_file}: {e}")
        return

    # Add chapters to XML tree (in memory)
    tree_with_chapters = add_chapters_to_xml_tree(tree, video_info)
    
    # Convert to markdown
    xml_tree_to_markdown(tree_with_chapters, video_info, output_file, split_chapters)

def main():
    parser = argparse.ArgumentParser(description='Convert XML subtitle file to markdown with chapter information')
    parser.add_argument('xml_file', help='Input XML subtitle file')
    parser.add_argument('info_file', help='JSON file containing video and chapter information')
    parser.add_argument('-o', '--output', required=True, help='Output markdown file path (or directory name when using --split)')
    parser.add_argument('--split', action='store_true', help='Create separate markdown files for each chapter')
    
    args = parser.parse_args()
    process_xml_to_markdown(args.xml_file, args.info_file, args.output, args.split)

if __name__ == '__main__':
    main() 