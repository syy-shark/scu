"""
Python Client for Smooth Computer Use Engine
Replicating Codex/ChatGPT Desktop CUA Smooth Motion & Accessibility Automation.
"""

import subprocess
import json
import os
from typing import List, Dict, Optional, Tuple

EXECUTABLE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "smooth-computer-use")

class SmoothComputerUse:
    def __init__(self, binary_path: str = EXECUTABLE_PATH):
        self.binary_path = binary_path
        if not os.path.exists(self.binary_path):
            raise FileNotFoundError(
                f"Binary not found at {self.binary_path}. Please run `bash build.sh` first."
            )

    def _run(self, *args: str) -> str:
        cmd = [self.binary_path] + list(args)
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0 and "⚠️" not in proc.stdout:
            raise RuntimeError(f"Command {' '.join(cmd)} failed: {proc.stderr}")
        return proc.stdout

    def run_demo(self):
        """Run the silky-smooth virtual cursor visual demo across the screen."""
        print("[*] Running visual cursor animation demo...")
        self._run("demo")

    def move(self, x: float, y: float):
        """Smoothly glides virtual cursor to (x, y) using Bezier arc + physics."""
        self._run("move", str(x), str(y))

    def click(self, x: float, y: float):
        """Smoothly glides virtual cursor to (x, y) and performs a click with ripple animation."""
        self._run("click", str(x), str(y))

    def list_apps(self) -> List[str]:
        """Lists active running GUI applications."""
        output = self._run("apps")
        apps = []
        for line in output.splitlines():
            line = line.strip()
            if line.startswith("• "):
                apps.append(line[2:])
        return apps

    def inspect_tree(self, app_name: str) -> List[Dict]:
        """
        Inspects UI Accessibility Tree for a target application,
        returning indexed elements.
        """
        output = self._run("tree", app_name)
        elements = []
        for line in output.splitlines():
            line = line.strip()
            if line.startswith("[") and "]" in line:
                elements.append(line)
        return elements

    def click_element(self, app_name: str, element_index: int):
        """Smoothly curves to the indexed UI element in app_name and clicks it."""
        return self._run("click-elem", app_name, str(element_index))

    def type_text(self, text: str):
        """Types text with natural human keystroke cadence."""
        return self._run("type", text)


if __name__ == "__main__":
    cua = SmoothComputerUse()
    print("✨ Active Apps:")
    for app in cua.list_apps()[:5]:
        print("  -", app)
    print("\n👉 Run cua.run_demo() to see the smooth cursor animation in action!")
