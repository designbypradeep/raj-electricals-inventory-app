from PIL import Image
import os

def zoom_at_center(image_path, zoom_factor=1.01):
    try:
        img = Image.open(image_path)
        w, h = img.size
        
        # Calculate crop box
        # We want to keep the center, so we crop the edges
        # The new view window size in original coordinates:
        crop_w = w / zoom_factor
        crop_h = h / zoom_factor
        
        left = (w - crop_w) / 2
        top = (h - crop_h) / 2
        right = (w + crop_w) / 2
        bottom = (h + crop_h) / 2
        
        # Crop the center
        img = img.crop((left, top, right, bottom))
        
        # Resize back to original size
        img = img.resize((w, h), Image.Resampling.LANCZOS)
        
        img.save(image_path)
        print(f"Successfully zoomed {image_path} by {zoom_factor}x")
        
    except Exception as e:
        print(f"Error processing {image_path}: {e}")

# Paths
base_dir = r"e:\Projects\raj_electricals_inventory_app\assets\icons"
icon_path = os.path.join(base_dir, "app_icon_shop.png")
fg_path = os.path.join(base_dir, "app_icon_shop_foreground.png")

# Apply zoom
zoom_at_center(icon_path)
zoom_at_center(fg_path)
