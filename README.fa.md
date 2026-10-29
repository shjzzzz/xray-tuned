# xray-tuned

> بسته استقرار و بهینه‌سازی پروکسی با کارایی بالا مبتنی بر **Xray-core (v26.10.29 stable)**.
> پشتیبانی پیش‌فرض از **XHTTP + Cloudflare CDN + Reality + Hysteria2** همراه با BBRv3، شتاب TCP Fast Open، بافر ایمن ۶۴ مگابایتی و توزیع خودکار اشتراک.

**زبان‌ها:** [简体中文](./README.md) · [English](./README.en.md) · **فارسی**

---

## ⚡ استقرار سریع
 
### ۱. استقرار خودکار و بی‌صدا Xray-Tuned (پیشنهادی)
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh) \
  AUTO=1 \
  REALITY_DOMAIN="reality.yourdomain.com" \
  CDN_DOMAIN="cdn.yourdomain.com" \
  NODE_TAG="US-Node" \
  FEATURE_REALITY_VISION=true \
  FEATURE_XHTTP_VLESSENC=true
```

### ۲. استقرار خودکار sbbox-tuned
```bash
bash <(curl -Ls https://raw.githubusercontent.com/shjzzzz/sbbox-tuned/main/sbbox.sh) hyp=1 anyp=1 nvp=1 tup=1 alns=1 sub=1 sbrel=pre ym=reality.yourdomain.com
```

### ۳. استقرار تعاملی
```bash
bash <(curl -fsSL https://github.com/shjzzzz/xray-tuned/releases/latest/download/install.sh)
```

---

## 📡 ماتریس ۱۰ نود اصلی
 
| ردیف | نام نود | پروتکل و انتقال | پورت / حالت | مبهم‌سازی / ویژگی | ویژگی و کاربرد پیشنهادی |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **۱** | `VLESS-TLS+PQ+XHTTP+CDN` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | رمزنگاری پساکوانتومی ML-KEM-768 + TLS 1.3 | **پیشنهاد اصلی روزمره**: شتاب امن جهانی CDN و مقاومت در برابر رمزگشایی کوانتومی |
| **۲** | `VLESS-TLS+PQ+Vision+XHTTP+CDN` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | جریان پویا Vision + ML-KEM-768 | حذف ردپای TLS-in-TLS و عبور از اختلالات شدید ساعات اوج |
| **۳** | `VLESS-REALITY+PQ+Vision（自域名）` | VLESS + REALITY (RAW) | 8447 / TCP (مستقیم) | ML-KEM-768 + Vision (پوشش 0.05ms) | **حداکثر سرعت مستقیم**: فناوری Zero-Copy و سرعت گیگابیتی با کمترین پینگ |
| **۴** | `VLESS-XHTTP-CDN-H2` | VLESS + XHTTP (H2) | 443 (Cloudflare CDN) | TLS 1.3 / xpadding / ۱۶ اتصال همزمان | ضد فیلتر و مخفی‌سازی کامل IP سرور با پشتیبانی از کلاینت‌های قدیمی |
| **۵** | `VLESS-XHTTP-CDN-H3` | VLESS + XHTTP (H3) | 443 (Cloudflare CDN) | شتاب CDN همراه با QUIC 0-RTT بافر ۶۴MB | بهترین شتاب روی اینترنت‌های موبایل و دارای پکت‌لاس |
| **۶** | `VLESS-XHTTP-Direct-H3` | VLESS + XHTTP (H3) | 8443 / UDP (مستقیم) | اتصال مستقیم QUIC / بافر ۶۴MB | اتصال مستقیم با تاخیر کم و پایداری بالا |
| **۷** | `Hysteria2-H3-Direct` | Hysteria2 | UDP پورت تصادفی (مثلا 19142) | BBRv3 / استاندارد HTTP/3 | حداکثر سرعت دانلود و بازیابی آنی بسته‌های از دست رفته |
| **۸** | `Hysteria2-TLS-BBR-Salamander` | Hysteria2 | UDP پورت تصادفی (مثلا 38969) | مبهم‌سازی Salamander + بافر ۶۴MB | عبور تضمینی از شدیدترین اختلالات و فیلترینگ ترافیک UDP |
| **۹** | `VLESS-Reality-Vision-Direct` | VLESS + REALITY (RAW) | 443 / TCP (پورت استاندارد) | اتصال مستقیم xtls-rprx-vision | پورت مستقیم ۴۴۳ با بالاترین اولویت شبکه |
| **۱۰** | `VLESS-Reality-XHTTP-Direct` | VLESS + REALITY (RAW) | 443 بازگشت به 8001 | XHTTP + رمزگشایی داخلی vlessenc | نود رزرو با پوشش ترکیبی پورت ۴۴۳ |

> [!NOTE]
> - نودهای ردیف ۱ تا ۳ مجهز به استاندارد NIST پساکوانتومی (ML-KEM-768) هستند.
> - نودهای هستریا (ردیف ۷ و ۸) با بافر ۶۴ مگابایت جریان و ۱۲۸ مگابایت اتصال بهینه‌سازی شده‌اند.
> - نود رزرو `VLESS-XHTTP-Direct-H2` (پورت 8445 TCP) در صورت نیاز با دستور `xh h2direct on` قابل فعال‌سازی است.

---

## 🛠️ دستور مدیریتی `xh`

```bash
xh status             # بررسی وضعیت سرویس‌ها، پورت‌ها و پارامترهای BBR
xh info               # مشاهدهٔ مشخصات نودها و لینک‌های اتصال
xh sub                # نمایش آدرس‌های سابسکریپشن و کد QR
xh reality            # مدیریت و روشن/خاموش کردن نودهای Reality
xh restart            # راه‌اندازی مجدد سرویس‌های Xray و Nginx
xh log xray           # بررسی لاگ زندهٔ اتصالات
xh tuning on|off      # فعال‌سازی یا لغو بهینه‌سازی سیستمی BBRv3
xh update             # به‌روزرسانی هستهٔ Xray (نسخهٔ رسمی و پایدار)
xh cert show|dnscf    # بررسی گواهی SSL یا تنظیم تمدید خودکار Cloudflare DNS-01
xh argo status|update # وضعیت تونل Cloudflare Argo و به‌روزرسانی هسته cloudflared
xh warp status|update # وضعیت خروجی Cloudflare WARP و دریافت مجدد کلید WireGuard
```

---

## 🔒 مدیریت گواهی SSL/TLS با Cloudflare

این پروژه امکان صدور خودکار و بهینهٔ گواهی SSL را با دو روش استاندارد فراهم می‌کند:

### روش ۱: صدور خودکار با Cloudflare DNS-01 API Token (پیشنهادی)
با استفاده از چالش DNS کلودفلر، **بدون نیاز به باز بودن پورت ۸۰ یا رفع فیلتر شبکه**، گواهی معتبر Let's Encrypt صادر و ماهانه به‌طور خودکار تمدید می‌شود:
```bash
CF_Token="کد_توکن_کلودفلر" xh cert dnscf
```

### روش ۲: گواهی Cloudflare Origin CA (اعتبار ۱۵ ساله)
در صورتی که دامنهٔ شما از پروکسی کلودفلر (ابر روشن) عبور می‌کند، می‌توانید از Origin CA استفاده کنید:
۱. از داشبورد کلودفلر به بخش **SSL/TLS -> Origin Server** رفته و یک گواهی ۱۵ ساله ایجاد کنید؛
۲. گواهی را در `/etc/nginx/certs/fullchain.cer` و کلید خصوصی را در `/etc/nginx/certs/cert.key` ذخیره کنید؛
۳. با دستور `xh restart` سرویس را ریلود کرده و حالت رمزنگاری را روی **Full (Strict)** قرار دهید.

---

## ☁️ مدیریت تونل Cloudflare Argo و WARP

- **تونل Cloudflare Argo (`cloudflared`)**:
  - `xh argo status`: بررسی نسخه هسته `cloudflared` و وضعیت اجرای سرویس؛
  - `xh argo update`: دانلود و به‌روزرسانی آخرین نسخه رسمی `cloudflared` (نسخه **`2026.10.3`**)؛
  - `xh argo on <token>`: تنظیم توکن تونل Zero Trust و راه‌اندازی خودکار سرویس؛
  - `xh argo off`: غیرفعال‌سازی و توقف سرویس تونل.
- **خروجی Cloudflare WARP**:
  - `xh warp status`: بررسی وضعیت IPv6 و گواهی WireGuard خروجی؛
  - `xh warp update`: تولید یا تمدید کلیدهای رسمی WireGuard جهت رفع تحریم و بازگشایی سرویس‌های OpenAI، ChatGPT، Claude و Netflix.
