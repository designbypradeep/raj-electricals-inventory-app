from PIL import Image
import sys

try:
    img = Image.open("assets/icons/app_icon.png")
    # Zoom in by cropping.
    # Crop 15% from all sides to scaling up the logo in the viewport
    w, h = img.size
    crop_percent = 0.15
    left = w * crop_percent
    top = h * crop_percent
    right = w - left
    bottom = h - top
    img_cropped = img.crop((left, top, right, bottom))
    img_resizes = img_cropped.resize((w, h), Image.Resampling.LANCZOS)
    img_resizes.save("assets/icons/app_icon_large.png")
    
    # Also for shop
    img_shop = Image.open("assets/icons/app_icon_shop.png")
    img_shop_cropped = img_shop.crop((left, top, right, bottom))
    img_shop_resizes = img_shop_cropped.resize((w, h), Image.Resampling.LANCZOS)
    img_shop_resizes.save("assets/icons/app_icon_shop_large.png")
    
    print("Success")
except Exception as e:
    print(e)
