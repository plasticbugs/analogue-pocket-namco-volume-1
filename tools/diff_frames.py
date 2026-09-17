#!/usr/bin/env python3
"""Diff a sim PPM frame against a reference PNG; report per-16px-cell counts
and write a visual diff (matching pixels dimmed, differing pixels red).

Usage: diff_frames.py <frame.ppm> <ref.png> [diff_out.png]
"""
import sys, zlib, struct

def read_ppm(path):
    f = open(path,'rb'); assert f.readline().strip()==b'P6'
    w,h = map(int, f.readline().split()); f.readline()
    return w, h, bytearray(f.read())

def read_png(path):
    d = open(path,'rb').read(); pos=8; idat=b''
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]; tag = d[pos+4:pos+8]
        if tag==b'IHDR':
            w,h,bd,ct = struct.unpack('>IIBB', d[pos+8:pos+18]); ch={2:3,6:4,3:1}[ct]; plte=None
        if tag==b'PLTE': plte=d[pos+8:pos+8+ln]
        if tag==b'IDAT': idat+=d[pos+8:pos+8+ln]
        pos+=12+ln
    raw=zlib.decompress(idat); stride=w*ch; img=bytearray(w*h*3); prev=bytearray(stride); p=0
    for y in range(h):
        fl=raw[p]; row=bytearray(raw[p+1:p+1+stride]); p+=1+stride
        for x in range(stride):
            a=row[x-ch] if x>=ch else 0; b_=prev[x]; c=prev[x-ch] if x>=ch else 0
            if fl==1: row[x]=(row[x]+a)&0xff
            elif fl==2: row[x]=(row[x]+b_)&0xff
            elif fl==3: row[x]=(row[x]+(a+b_)//2)&0xff
            elif fl==4:
                pp=a+b_-c; pa,pb,pc=abs(pp-a),abs(pp-b_),abs(pp-c)
                pr=a if (pa<=pb and pa<=pc) else (b_ if pb<=pc else c)
                row[x]=(row[x]+pr)&0xff
        prev=row
        for x in range(w):
            if ch==1: pi=row[x]*3; img[(y*w+x)*3:(y*w+x)*3+3]=plte[pi:pi+3]
            else: img[(y*w+x)*3:(y*w+x)*3+3]=row[x*ch:x*ch+3]
    return w,h,img

def write_png(path, w, h, img):
    raw = b''.join(b'\x00'+bytes(img[y*w*3:(y+1)*w*3]) for y in range(h))
    def chunk(tag,d): c=tag+d; return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c))
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))
                          +chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b''))

def main():
    a = read_ppm(sys.argv[1]) if sys.argv[1].endswith('.ppm') else read_png(sys.argv[1])
    b = read_png(sys.argv[2])
    assert a[0]==b[0] and a[1]==b[1], (a[:2], b[:2])
    w, h = a[0], a[1]
    ia, ib = a[2], b[2]
    diff = 0; cells = {}
    out = bytearray(w*h*3)
    for i in range(0, len(ia), 3):
        if ia[i:i+3] != ib[i:i+3]:
            diff += 1
            y, x = (i//3)//w, (i//3)%w
            cells[(y//16, x//16)] = cells.get((y//16,x//16), 0) + 1
            out[i:i+3] = b'\xff\x00\x00'
        else:
            out[i] = ia[i]//3; out[i+1] = ia[i+1]//3; out[i+2] = ia[i+2]//3
    total = len(ia)//3
    print(f'diff {diff}/{total} ({100*diff/total:.3f}%)')
    for k, n in sorted(cells.items(), key=lambda x:-x[1])[:14]:
        print(f'  cell row{k[0]:2d} col{k[1]:2d}: {n} px')
    if len(sys.argv) > 3:
        write_png(sys.argv[3], w, h, out)

if __name__ == '__main__':
    main()
