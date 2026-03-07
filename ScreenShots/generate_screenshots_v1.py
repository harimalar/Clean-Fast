import os
from PIL import Image, ImageDraw, ImageFont

# Settings
SOURCE_DIR = "/Users/harirajzgopal/Desktop/Malar xCode/Active Projects/ClearFast/Fasting/FastingTracker/ScreenShots"
OUTPUT_DIR_IPHONE = os.path.join(SOURCE_DIR, "iPhone_6.5")
OUTPUT_DIR_IPAD = os.path.join(SOURCE_DIR, "iPad_13")

# Dimensions
IPHONE_SIZE = (1284, 2778)
IPAD_SIZE = (2048, 2732)

# Taglines
TAGLINES = [
    "MASTER YOUR FASTING JOURNEY",
    "POWERFUL ANALYTICS, PRO RESULTS",
    "YOUR PERSONAL METABOLIC COACH",
    "ADVANCED PROTOCOLS & GUIDANCE",
    "EFFORTLESS HISTORY TRACKING",
    "ONE PURCHASE, LIFETIME ACCESS"
]

# Source Images
IMAGES = ["IMG_5460.png", "IMG_5461.png", "IMG_5462.png", "IMG_5463.png", "IMG_5464.png", "IMG_5465.png"]

def draw_wrapped_text(draw, text, font, color, max_width, top_gap_height, output_size):
    lines = []
    words = text.split()
    
    while words:
        line = ''
        while words and draw.textbbox((0, 0), line + words[0], font=font)[2] <= max_width:
            line += words.pop(0) + ' '
        lines.append(line.strip())
    
    # Calculate total height of the text block
    line_bboxes = [draw.textbbox((0, 0), line, font=font) for line in lines]
    line_heights = [bbox[3] - bbox[1] for bbox in line_bboxes]
    total_text_height = sum(line_heights) + (len(lines) - 1) * 30 # 30px line spacing
    
    # Start Y to center vertically in the top gap
    current_y = (top_gap_height - total_text_height) // 2
    
    for i, line in enumerate(lines):
        line_w = line_bboxes[i][2] - line_bboxes[i][0]
        x = (output_size[0] - line_w) // 2
        
        # Draw shadow
        draw.text((x + 3, current_y + 3), line, font=font, fill=(0, 0, 0, 180))
        # Draw text
        draw.text((x, current_y), line, font=font, fill=color)
        current_y += line_heights[i] + 30

def create_screenshot(source_name, tagline, output_size, output_path, is_ipad=False):
    # Create solid black background
    bg = Image.new("RGB", output_size, (0, 0, 0)) 
    draw = ImageDraw.Draw(bg)
    
    # Load and resize source image
    source_img = Image.open(os.path.join(SOURCE_DIR, source_name))
    
    # Calculate source image placement
    if is_ipad:
        inner_w = int(output_size[0] * 0.75)  # Slightly smaller to leave room for text
        inner_h = int(source_img.height * (inner_w / source_img.width))
        source_resized = source_img.resize((inner_w, inner_h), Image.Resampling.LANCZOS)
        pos_x = (output_size[0] - inner_w) // 2
        pos_y = 800  # Start below the tagline area
    else:
        inner_w = int(output_size[0] * 0.88)
        inner_h = int(source_img.height * (inner_w / source_img.width))
        source_resized = source_img.resize((inner_w, inner_h), Image.Resampling.LANCZOS)
        pos_x = (output_size[0] - inner_w) // 2
        pos_y = 700 # Plenty of room for multi-line text

    # Add shadow/glow effect
    shadow = Image.new("RGBA", (inner_w + 60, inner_h + 60), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow)
    # Subtle white glow to separate from black background
    s_draw.rounded_rectangle([10, 10, inner_w + 50, inner_h + 50], radius=70, fill=(255, 255, 255, 30)) 
    bg.paste(shadow, (pos_x - 30, pos_y - 30), shadow)

    # Paste app screen
    mask = Image.new("L", (inner_w, inner_h), 0)
    m_draw = ImageDraw.Draw(mask)
    m_draw.rounded_rectangle([0, 0, inner_w, inner_h], radius=60, fill=255)
    bg.paste(source_resized, (pos_x, pos_y), mask)

    # Add Tagline
    try:
        font_path = "/System/Library/Fonts/SFNS.ttf" 
        if not os.path.exists(font_path):
            font_path = "/System/Library/Fonts/Helvetica.ttc"
            
        font_size = 110 if not is_ipad else 160 
        font = ImageFont.truetype(font_path, font_size)
    except:
        font = ImageFont.load_default()

    # Draw wrapped text with margins
    margin = output_size[0] * 0.12 # 12% margin
    draw_wrapped_text(draw, tagline, font, (255, 255, 255), output_size[0] - 2 * margin, pos_y, output_size)

    # Save
    bg.save(output_path, "PNG")

def main():
    os.makedirs(OUTPUT_DIR_IPHONE, exist_ok=True)
    os.makedirs(OUTPUT_DIR_IPAD, exist_ok=True)

    for i, (img_name, tagline) in enumerate(zip(IMAGES, TAGLINES)):
        print(f"Processing {img_name}...")
        
        # iPhone
        iphone_path = os.path.join(OUTPUT_DIR_IPHONE, f"Screen_{i+1}.png")
        create_screenshot(img_name, tagline, IPHONE_SIZE, iphone_path, is_ipad=False)
        
        # iPad
        ipad_path = os.path.join(OUTPUT_DIR_IPAD, f"Screen_{i+1}.png")
        create_screenshot(img_name, tagline, IPAD_SIZE, ipad_path, is_ipad=True)

    print("Done!")

if __name__ == "__main__":
    main()
