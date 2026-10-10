/**
 * Node.js / JavaScript Client for Smooth Computer Use Engine
 * Replicating Codex/ChatGPT Desktop CUA Smooth Motion & Accessibility Automation.
 */

const { execFileSync } = require('child_process');
const path = require('path');

const BINARY_PATH = path.join(__dirname, 'smooth-computer-use');

class SmoothComputerUse {
  constructor(binaryPath = BINARY_PATH) {
    this.binaryPath = binaryPath;
  }

  _run(args) {
    return execFileSync(this.binaryPath, args, { encoding: 'utf-8' });
  }

  /** Run the visual cursor physics & animation demo */
  runDemo() {
    return this._run(['demo']);
  }

  /** Smoothly glide cursor to (x, y) with Bezier curve */
  move(x, y) {
    return this._run(['move', String(x), String(y)]);
  }

  /** Smoothly glide to (x, y) and click with ripple animation */
  click(x, y) {
    return this._run(['click', String(x), String(y)]);
  }

  /** List active running GUI applications */
  listApps() {
    const output = this._run(['apps']);
    return output
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.startsWith('• '))
      .map(line => line.slice(2));
  }

  /** Inspect accessibility tree with integer element IDs */
  inspectTree(appName) {
    const output = this._run(['tree', appName]);
    return output
      .split('\n')
      .map(line => line.trim())
      .filter(line => line.startsWith('[') && line.includes(']'));
  }

  /** Glide smoothly to indexed UI element and click it */
  clickElement(appName, elementIndex) {
    return this._run(['click-elem', appName, String(elementIndex)]);
  }

  /** Type text into active focus */
  typeText(text) {
    return this._run(['type', text]);
  }
}

module.exports = { SmoothComputerUse };

if (require.main === module) {
  const cua = new SmoothComputerUse();
  console.log('✨ Active Apps:');
  console.log(cua.listApps().slice(0, 5));
  console.log('\n👉 Run `node -e "new (require(\'./index.js\').SmoothComputerUse)().runDemo()"` to see the demo!');
}
