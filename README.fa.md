# xray-tuned

> بسته استقرار و بهینه‌سازی پروکسی با کارایی بالا مبتنی بر **Xray-core (v26.3.27 stable)**.
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
| **۶** | `VLESS-XHTTP-Direct-H3` | VLESS + XHTTP (H3) | 8446 / UDP (مستقیم) | اتصال مستقیم QUIC / بافر ۶۴MB | اتصال مستقیم با تاخیر کم و پایداری بالا |
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
```
