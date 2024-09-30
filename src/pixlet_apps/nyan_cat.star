"""
Applet: Nyan Cat
Summary: Nyan Cat Animation
Description: An animated cartoon cat with a Pop-Tart for a torso.
Author: Mack Ward
"""

load("encoding/base64.star", "base64")
load("render.star", "render")
load("schema.star", "schema")

FRAMES = [
    """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""",
]

def main():
    return render.Root(
        child = render.Animation(
            children = [render.Image(src = base64.decode(f)) for f in FRAMES],
        ),
    )

def get_schema():
    return schema.Schema(version = "1", fields = [])