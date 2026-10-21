// Zmenšování obrázků v prohlížeči před nahráním (fotky z telefonu i velké výkresy).
async function toBlob(bitmap, maxSide, quality) {
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
  const c = Object.assign(document.createElement('canvas'), { width: Math.round(bitmap.width * scale), height: Math.round(bitmap.height * scale) });
  const ctx = c.getContext('2d');
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height); // průhledné PNG na bílé pozadí
  ctx.drawImage(bitmap, 0, 0, c.width, c.height);
  const blob = await new Promise((r) => c.toBlob(r, 'image/jpeg', quality));
  return { blob, width: c.width, height: c.height };
}

// Hlavní obrázek: nejvýš maxSide px (výkresy potřebují detail), náhled: 800 px.
export async function prepareImage(file, maxSide = 3200) {
  const bmp = await createImageBitmap(file);
  const keep = Math.max(bmp.width, bmp.height) <= maxSide && file.size < 4_000_000 && /jpeg|png|webp/.test(file.type);
  const main = keep ? { blob: file, width: bmp.width, height: bmp.height } : await toBlob(bmp, maxSide, 0.88);
  const thumb = await toBlob(bmp, 800, 0.8);
  bmp.close?.();
  return { main, thumb, type: keep ? file.type : 'image/jpeg' };
}
