# کسبمن موبایل

اپلیکیشن مستقل Flutter برای Android و iOS. این برنامه با وب‌اپ Next.js یکی نیست؛ هر دو فقط از بک‌اند مشترک کسبمن استفاده می‌کنند.

## وضعیت

- اتصال به Supabase با `supabase_flutter` نسخه 2.18.3
- ورود و ثبت‌نام با ایمیل و رمز عبور
- حفظ نشست کاربر و ورود خودکار پس از اجرای مجدد
- خروج از حساب
- رابط فارسی و راست‌چین
- داشبورد اولیه پس از ورود

## نیازمندی‌ها

- Flutter stable و Dart سازگار با محدودیت SDK در `pubspec.yaml`
- Android Studio / Android SDK برای ساخت Android
- Xcode روی macOS برای ساخت iOS

## راه‌اندازی محلی

ابتدا فایل‌های بومی Android و iOS را با Flutter SDK تولید کن:

```bash
flutter create --platforms=android,ios .
flutter pub get
```

آدرس پروژه و کلید عمومی Supabase را از تنظیمات پروژه بردار و به‌صورت compile-time تعریف کن. برای نمونه:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SB_PUBLISHABLE_KEY
```

این دو مقدار برای کلاینت عمومی هستند. هرگز کلید secret یا service-role را داخل اپ، مخزن یا فایل‌های قابل انتشار قرار نده.

برای بررسی:

```bash
flutter analyze --fatal-infos
flutter test
```

## اصول اتصال به بک‌اند

- استفاده از همان Supabase project وب‌اپ.
- هیچ service-role یا secret key داخل اپ قرار نگیرد.
- مجوزها و جداسازی کسب‌وکارها در PostgreSQL/RLS enforce شوند.
- هر درخواست باید business/workspace فعال را به‌صورت صریح و امن تعیین کند.
- برای قابلیت آفلاین، عملیات محلی با outbox، شناسه idempotency و سیاست حل تعارض همگام شوند؛ تا قبل از طراحی و تست، نوشتن آفلاین روی داده‌های حساس مالی فعال نشود.

## محدوده بعدی

مرحله بعدی پس از احراز هویت: دریافت کسب‌وکارهایی که کاربر عضو آن‌هاست، انتخاب فضای کاری و نمایش داشبورد متناسب با نقش و دسترسی او.
