// Script to capture STT initialization logs
const puppeteer = require('puppeteer');

(async () => {
  const browser = await puppeteer.launch({
    headless: false,
    devtools: true,
    args: ['--disable-web-security', '--disable-features=VizDisplayCompositor']
  });

  const page = await browser.newPage();

  // Capture all console messages
  const logs = [];
  page.on('console', msg => {
    const timestamp = new Date().toISOString();
    const level = msg.type();
    const text = msg.text();
    const logEntry = `[${timestamp}] ${level.toUpperCase()}: ${text}`;
    console.log(logEntry);
    logs.push(logEntry);
  });

  // Navigate to the test page
  await page.goto('http://localhost:3000/test-stt', { waitUntil: 'networkidle0' });

  console.log('=== Page loaded, waiting 2 seconds before clicking Initialize STT ===');
  await page.waitForTimeout(2000);

  // Click the Initialize STT button
  await page.evaluate(() => {
    const buttons = Array.from(document.querySelectorAll('button'));
    const initButton = buttons.find(btn => btn.textContent?.includes('Initialize STT'));
    if (initButton) {
      console.log('[Script] Clicking Initialize STT button');
      initButton.click();
    } else {
      console.log('[Script] Initialize STT button not found');
    }
  });

  console.log('=== Button clicked, waiting 10 seconds to capture initialization logs ===');
  await page.waitForTimeout(10000);

  console.log('\n=== CAPTURED LOGS SUMMARY ===');
  logs.forEach(log => console.log(log));

  console.log('\n=== Closing browser ===');
  await browser.close();
})().catch(console.error);
