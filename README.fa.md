# xray-tuned

> بسته استقرار و بهینه‌سازی پروکسی با کارایی بالا مبتنی بر **Xray-core (v26.3.27 stable)**.
> پشتیبانی پیش‌فرض از **XHTTP + Cloudflare CDN + Reality + Hysteria2** همراه با BBRv3، شتاب TCP Fast Open، بافر ایمن ۶۴ مگابایتی و توزیع خودکار اشتراک.

**زبان‌ها:** [简体中文](./README.md) · [English](./README.en.md) · **فارسی**

---

## ⚡ استقرار سریع

### ۱. استقرار تعاملی
```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/shjzzzz/xray-tuned/main/dist/install.sh)
```

### ۲. استقرار خودکار و بدون پرسش
```bash
sudo env AUTO=1 \
  REALITY_DOMAIN="reality.example.com" \
  CDN_DOMAIN="cdn.example.com" \
  NODE_TAG="my-vps" \
  bash <(curl -fsSL https://raw.githubusercontent.com/shjzzzz/xray-tuned/main/dist/install.sh)
```

---

## 📡 نودهای اصلی

| ردیف | نام نود | پروتکل | پورت / انتقال | ویژگی و کاربرد |
| :---: | :--- | :--- | :--- | :--- |
| **۱** | `VLESS-XHTTP-CDN-H2` | VLESS + XHTTP | 443 (CF CDN) / h2 | ضد فیلتر و مخفی‌سازی کامل IP سرور |
| **۲** | `VLESS-XHTTP-CDN-H3` | VLESS + XHTTP | 443 (CF CDN) / h3 | شتاب CDN همراه با QUIC 0-RTT |
| **۳** | `VLESS-XHTTP-Direct-H3` | VLESS + XHTTP | 8446 / h3 (UDP) | سرعت بالا و تاخیر کم مستقیم QUIC |
| **۴** | `VLESS-XHTTP-Direct-H2` | VLESS + XHTTP | 8445 / h2 (TCP) | اتصال مستقیم TCP برای زمان مسدودی UDP |
| **۵** | `Hysteria2-H3-Direct` | Hysteria2 | 33385 / UDP | حداکثر سرعت و بازیابی عالی در شبکه‌های با پکت‌لاس |
| **۶** | `Hysteria2-Obfs-Direct` | Hysteria2 | 37987 / UDP | مبهم‌سازی Salamander برای دور زدن فیلترینگ شدید |
| **۷** | `VLESS-Reality-Vision-Direct` | VLESS + Reality | 443 / TCP (RAW) | **پیشنهاد اصلی**؛ کمترین تاخیر و فناوری Zero-Copy |
| **۸** | `VLESS-Reality-PQ-Vision` | VLESS + Reality | 8447 / TCP (RAW) | رمزنگاری پساکوانتومی امن در برابر محاسبات کوانتومی |

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
