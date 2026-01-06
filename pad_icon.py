from PIL import Image

def add_padding(input_path, output_path, scale_factor=0.65):
    try:
        img = Image.open(input_path).convert("RGBA")
        width, height = img.size
        
        # Calculate new size
        new_width = int(width * scale_factor)
        new_height = int(height * scale_factor)
        
        # Resize the image
        img_resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # Create a new transparent background
        new_img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        
        # Calculate centering position
        x_offset = (width - new_width) // 2
        y_offset = (height - new_height) // 2
        
        # Paste centered
        new_img.paste(img_resized, (x_offset, y_offset), img_resized)
        
        new_img.save(output_path)
        print(f"Processed {input_path} -> {output_path} (Scale: {scale_factor})")
        
    except Exception as e:
        print(f"Error processing {input_path}: {e}")

if __name__ == "__main__":
    # Pad the transparent icons we generated earlier
    add_padding("assets/icons/app_icon_transparent.png", "assets/icons/app_icon_foreground.png", 0.65)
    add_padding("assets/icons/app_icon_shop_transparent.png", "assets/icons/app_icon_shop_foreground.png", 0.65)
