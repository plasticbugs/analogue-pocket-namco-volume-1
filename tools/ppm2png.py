#!/usr/bin/env python3
"""Convert a binary PPM (P6) to PNG: ppm2png.py in.ppm out.png"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio
d = open(sys.argv[1], 'rb').read()
parts = d.split(b'\n', 3)
w, h = map(int, parts[1].split())
pngio.write(sys.argv[2], w, h, parts[3][:w * h * 3])
