"""Generate the app's code-drawn terrain icon (developer-only; needs Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw
import json
import math

root=Path(__file__).resolve().parent
palette=json.loads((root/'RdBu_r.json').read_text())
image=Image.new('RGBA',(1024,1024))
draw=ImageDraw.Draw(image)
draw.rounded_rectangle((40,40,984,984),radius=210,fill='#172936')

def point(i,j):
    x=(i-10)/10;y=(j-10)/10
    z=0.8*math.sin(2.4*x)*math.cos(2.4*y)+0.3*math.cos(5*x+2*y)
    return (512+210*(x-y),610+105*(x+y)-180*z),z

for total in range(40):
    for i in range(20):
        j=total-i
        if not 0<=j<20:continue
        cell=[point(i,j),point(i+1,j),point(i+1,j+1),point(i,j+1)]
        for triangle in [(0,1,2),(0,2,3)]:
            z=sum(cell[k][1] for k in triangle)/3
            rgba=palette[min(255,max(0,int((z+1.1)/2.2*255)))]
            color=tuple(round(v*255) for v in rgba)
            draw.polygon([cell[k][0] for k in triangle],fill=color)
iconset=root/'AppIcon.iconset';iconset.mkdir(exist_ok=True)
for size in [16,32,128,256,512]:
    for factor in [1,2]:
        name=f'icon_{size}x{size}'+('@2x' if factor==2 else '')+'.png'
        image.resize((size*factor,size*factor),Image.Resampling.LANCZOS).save(iconset/name)
image.save(root/'AppIcon.icns', format='ICNS')
