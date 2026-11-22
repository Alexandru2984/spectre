// Exercise advanced actions through the same native disclosure as a user.
export async function openRoomTool(page, selector) {
  const tools = page.locator('#room-tools');
  if (!await tools.evaluate(node => node.open)) await tools.locator('summary').click();
  await page.locator(selector).click();
}
