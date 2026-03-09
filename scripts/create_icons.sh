#!/bin/bash

# Check if input file is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    echo "Example: $0 Icons/icon.png"
    exit 1
fi

input_file="$1"

# Check if input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist"
    exit 1
fi

# Check if file is a PNG
if [[ ! "$input_file" =~ \.png$ ]]; then
    echo "Error: Input file must be a PNG file"
    exit 1
fi

# Create AppIcon.appiconset directory if it doesn't exist
appiconset_dir="TodoApp/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$appiconset_dir"

# Create Contents.json for AppIcon set
cat > "$appiconset_dir/Contents.json" << 'EOL'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_64x64.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "64x64"
    },
    {
      "filename" : "icon_64x64@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "64x64"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_1024x1024.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOL

# Get the base filename without extension
filename=$(basename -- "$input_file")
name="${filename%.*}"
    
echo "Processing $filename..."

# Array of required sizes
sizes=(16 32 64 128 256 512 1024)

# Generate icons for each size
for size in "${sizes[@]}"; do
    # Generate @1x size
    output_file="icon_${size}x${size}.png"
    sips -z $size $size "$input_file" --out "$appiconset_dir/$output_file"
    echo "Created $output_file"
    
    # Generate @2x size (except for 1024)
    if [ $size -ne 1024 ]; then
        output_file_2x="icon_${size}x${size}@2x.png"
        sips -z $((size * 2)) $((size * 2)) "$input_file" --out "$appiconset_dir/$output_file_2x"
        echo "Created $output_file_2x"
    fi
done

echo "All icons created successfully in Assets.xcassets!" 