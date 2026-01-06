from PIL import Image
import math

def remove_background(input_path, output_path, target_color_hex):
    img = Image.open(input_path).convert("RGBA")
    datas = img.getdata()
    
    # Auto-detect background color from top-left pixel if not provided
    if target_color_hex is None:
        bg_pixel = img.getpixel((0, 0))
        tr, tg, tb = bg_pixel[0], bg_pixel[1], bg_pixel[2]
        print(f"Auto-detected background color: ({tr}, {tg}, {tb})")
    else:
        # Parse hex color
        target_color_hex = target_color_hex.lstrip('#')
        tr = int(target_color_hex[0:2], 16)
        tg = int(target_color_hex[2:4], 16)
        tb = int(target_color_hex[4:6], 16)
    
    target_rgb = (tr, tg, tb)
    
    threshold = 50 # Color distance threshold
    
    newData = []
    for item in datas:
        # Euclidean distance
        r, g, b, a = item
        distance = math.sqrt((r - tr)**2 + (g - tg)**2 + (b - tb)**2)
        
        if distance < threshold:
            newData.append((255, 255, 255, 0)) # Make transparent
        else:
            newData.append(item)
            
    img.putdata(newData)
    img.save(output_path, "PNG")
    print(f"Processed {input_path} -> {output_path}")

try:
    # Use the brand color found in app_theme.dart: 0xFFC1441E -> #C1441E
    brand_color = "C1441E" 
    remove_background("assets/icons/app_icon.png", "assets/icons/app_icon_transparent.png", brand_color)
    remove_background("assets/icons/app_icon_shop.png", "assets/icons/app_icon_shop_transparent.png", brand_color)
    print("Success")
except Exception as e:
    print(f"Error: {e}")
