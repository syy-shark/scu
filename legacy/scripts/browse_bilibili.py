#!/usr/bin/env python3
"""
Orchestration Script: Smooth Computer Use on Bilibili via Google Chrome
Delegates to the native single-session Swift overlay engine for 120 FPS fluid cursor physics.
"""

import subprocess
import os
import sys

BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "smooth-computer-use")

def main():
    print("=" * 60)
    print("🎬 Launching Ultra-Smooth Continuous Bilibili Browsing Session")
    print("=" * 60)

    # Execute native continuous session
    cmd = [BIN, "bilibili"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in proc.stdout:
        print(line, end="")
    proc.wait()

if __name__ == "__main__":
    main()
