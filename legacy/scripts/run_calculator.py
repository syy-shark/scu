#!/usr/bin/env python3
import subprocess
import time
import sys

BIN = "/Users/shark/projects/smooth-computer-use/smooth-computer-use"

def run_cmd(*args):
    cmd = [BIN] + list(args)
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

def click_button(title):
    print(f"👉 Clicking '{title}'...")
    out = run_cmd("click", "--app", "计算器", "--title", title, "--role", "button")
    print(f"   {out}")
    time.sleep(0.3)

def clear_calc():
    for t in ["全部清除", "清除", "C", "AC"]:
        out = run_cmd("click", "--app", "计算器", "--title", t, "--role", "button")
        if "Clicked" in out:
            print(f"🧹 Cleared calculator: {out}")
            time.sleep(0.3)
            return

def get_calc_state():
    out = run_cmd("state", "计算器")
    return out

def get_calc_result():
    state = get_calc_state()
    for line in state.splitlines():
        if "编辑字段" in line and "value=" in line:
            return line.strip()
    return ""

def main():
    print("🚀 启动并激活计算器...")
    run_cmd("open-app", "Calculator", "--activate")
    time.sleep(0.8)

    print("\n🧹 步骤 1: 清空计算器")
    clear_calc()

    print("\n🧮 步骤 2: 计算 2026 × 42")
    keys_1 = ["2", "0", "2", "6", "乘", "4", "2", "等于"]
    for k in keys_1:
        click_button(k)

    res_1 = get_calc_result()
    print(f"✨ 运算 1 结果: {res_1}")
    time.sleep(1.0)

    print("\n🧹 步骤 3: 清除并进行下一轮计算 520 + 1314")
    clear_calc()

    keys_2 = ["5", "2", "0", "加", "1", "3", "1", "4", "等于"]
    for k in keys_2:
        click_button(k)

    res_2 = get_calc_result()
    print(f"✨ 运算 2 结果: {res_2}")

    # 截图留存
    screenshot_path = "/tmp/calculator_result.png"
    print(f"\n📸 捕获计算器窗口截图至 {screenshot_path}...")
    run_cmd("screenshot", "--app", "计算器", "--out", screenshot_path)
    print("✅ 全部计算器操作顺利完成！")

if __name__ == "__main__":
    main()
