// التطبيق انتقل إلى /app/: هذا يشيل النسخة القديمة من الجوال
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.registration.unregister()));
