#!/usr/bin/env python3
import subprocess
import time
import os
import re

BIN = "/Users/shark/projects/smooth-computer-use/smooth-computer-use"

def run_cmd(*args):
    cmd = [BIN] + list(args)
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

def pause(s):
    time.sleep(s)

def main():
    print("=" * 60)
    print("🎬 启动 Smooth Computer Use: Chrome Bilibili 多视频同步刷阅演示")
    print("=" * 60)

    # 1. 激活 Chrome
    print("\n👉 步骤 1: 激活 Chrome 浏览器窗口")
    run_cmd("open-app", "Google Chrome", "--activate")
    pause(1.0)

    # 2. 获取当前页面状态
    print("\n👉 步骤 2: 获取 B站 首页状态与视频推荐流")
    st = run_cmd("state", "Google Chrome", "--interactive")
    
    # 查找所有视频链接
    lines = st.splitlines()
    video_cards = []
    for line in lines:
        if "/video/BV" in line and "Link" in line:
            # 提取 id 与 标题
            m_id = re.search(r'\[(\d+)\]', line)
            m_url = re.search(r'url=(https://[^\s@]+)', line)
            m_title = re.search(r'Link "(.*?)"', line)
            if m_id and m_url:
                vid = int(m_id.group(1))
                url = m_url.group(1)
                title = m_title.group(1) if m_title else "视频"
                # 排除重复与非视频卡片
                if any(v["url"] == url for v in video_cards):
                    continue
                video_cards.append({"id": vid, "url": url, "title": title, "raw": line})

    print(f"  已识别到 {len(video_cards)} 个在屏视频卡片:")
    for i, v in enumerate(video_cards[:5]):
        print(f"   [{i+1}] (ID {v['id']}) {v['title'][:40]}... -> {v['url']}")

    # 选取 3 个精彩视频
    picks = video_cards[:3]
    if len(picks) < 3:
        print("视频不足 3 个，向下滚动获取更多...")
        run_cmd("scroll", "--app", "Google Chrome", "--dy", "-400")
        pause(1.0)
        st = run_cmd("state", "Google Chrome", "--interactive")
        # 重新选取
        video_cards = []
        for line in st.splitlines():
            if "/video/BV" in line and "Link" in line:
                m_id = re.search(r'\[(\d+)\]', line)
                m_url = re.search(r'url=(https://[^\s@]+)', line)
                m_title = re.search(r'Link "(.*?)"', line)
                if m_id and m_url:
                    vid = int(m_id.group(1))
                    url = m_url.group(1)
                    title = m_title.group(1) if m_title else "视频"
                    if any(v["url"] == url for v in video_cards):
                        continue
                    video_cards.append({"id": vid, "url": url, "title": title, "raw": line})
        picks = video_cards[:3]

    print("\n👉 步骤 3: 模拟拟人化自然光标，在首页依次平滑滑行并悬停预览 3 个视频 (触发帧预览)")
    for i, v in enumerate(picks):
        print(f"\n  🎯 悬停并划过第 {i+1} 个视频: {v['title'][:30]}")
        out = run_cmd("hover", "--app", "Google Chrome", "--id", str(v["id"]))
        print(f"     {out}")
        pause(1.2)

    print("\n👉 步骤 4: 后台新标签页同步打开这 3 个视频，实现【同时刷三个视频】")
    for i, v in enumerate(picks):
        print(f"  🚀 打开第 {i+1} 个视频标签页: {v['title'][:30]}...")
        # 提取或直接用 open_url
        run_cmd("open-url", v["url"], "--app", "Google Chrome")
        pause(0.8)

    print("\n⏳ 等待 3 个视频页面加载与视频流并发缓冲...")
    pause(3.0)

    # 截图首页
    run_cmd("screenshot", "--app", "Google Chrome", "--out", "/tmp/bilibili_home.png")

    print("\n👉 步骤 5: 平滑切换并巡检这 3 个正在播放的视频标签页")
    # 使用快捷键轮流切换标签页
    for i in range(1, 4):
        # cmd+Option+Right 或 cmd+数字
        # Tab 1 是主页，Tab 2/3/4 是刚打开的视频
        tab_key = f"cmd+{i+1}"
        print(f"\n  🎬 切换至正在播放的视频 {i} (快捷键 {tab_key})...")
        run_cmd("key", tab_key, "--app", "Google Chrome")
        pause(2.0)

        # 视频页面向下轻微滚动
        run_cmd("scroll", "--app", "Google Chrome", "--dy", "-150")
        pause(0.5)

        # 移动光标至播放器区域
        run_cmd("move", "600", "450")
        pause(0.5)

        # 截图留存
        shot_path = f"/tmp/bilibili_video_{i}.png"
        run_cmd("screenshot", "--app", "Google Chrome", "--out", shot_path)
        print(f"     📸 已截取视频 {i} 播放现场: {shot_path}")

    print("\n🎉 成功完成 Chrome 哔哩哔哩同时刷 3 个视频的平滑计算机控制全流程！")

if __name__ == "__main__":
    main()
