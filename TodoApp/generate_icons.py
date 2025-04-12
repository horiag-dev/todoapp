import os
import sys
from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
from PIL import Image

# Define the sizes we need
sizes = [
    (16, 16),    # 16x16
    (32, 32),    # 16x16@2x
    (32, 32),    # 32x32
    (64, 64),    # 32x32@2x
    (128, 128),  # 128x128
    (256, 256),  # 128x128@2x
    (256, 256),  # 256x256
    (512, 512),  # 256x256@2x
    (512, 512),  # 512x512
    (1024, 1024) # 512x512@2x
]

# Output filenames
filenames = [
    "icon_16x16.png",
    "icon_16x16@2x.png",
    "icon_32x32.png",
    "icon_32x32@2x.png",
    "icon_128x128.png",
    "icon_128x128@2x.png",
    "icon_256x256.png",
    "icon_256x256@2x.png",
    "icon_512x512.png",
    "icon_512x512@2x.png"
]

# Get the absolute path to the script's directory
script_dir = os.path.dirname(os.path.abspath(__file__))

# Input SVG path (using absolute path)
svg_path = os.path.join(script_dir, "Assets.xcassets/AppIcon.appiconset/icon.svg")
output_dir = os.path.join(script_dir, "Assets.xcassets/AppIcon.appiconset")

print(f"Script directory: {script_dir}")
print(f"SVG path: {svg_path}")
print(f"Output directory: {output_dir}")

# Check if SVG file exists
if not os.path.exists(svg_path):
    print(f"Error: SVG file not found at {svg_path}")
    sys.exit(1)

# Create output directory if it doesn't exist
os.makedirs(output_dir, exist_ok=True)

# Generate PNGs for each size
for size, filename in zip(sizes, filenames):
    output_path = os.path.join(output_dir, filename)
    print(f"\nProcessing {filename} ({size[0]}x{size[1]})")
    print(f"Output path: {output_path}")
    
    try:
        # Convert SVG to PNG
        drawing = svg2rlg(svg_path)
        renderPM.drawToFile(drawing, output_path, fmt="PNG", dpi=72)
        
        # Resize the image to the exact size
        img = Image.open(output_path)
        img = img.resize(size, Image.Resampling.LANCZOS)
        img.save(output_path)
        
        print(f"Successfully generated {filename}")
    except Exception as e:
        print(f"Error generating {filename}: {str(e)}")

print("\nIcon generation process completed!") 