import Link from "next/link";

const capabilities = [
  {
    number: "۰۱",
    title: "مدیریت یکپارچه",
    description: "ابزارهای اصلی کسب‌وکار در یک فضای منظم و هماهنگ.",
  },
  {
    number: "۰۲",
    title: "ساختار منعطف",
    description: "مدیریت چند کسب‌وکار، شعب، اعضا و سطح دسترسی.",
  },
  {
    number: "۰۳",
    title: "آماده توسعه",
    description: "معماری ماژولار برای رشد از کسب‌وکار کوچک تا سازمان بزرگ.",
  },
];

export default function HomePage() {
  return (
    <main className="shell">
      <header className="topbar">
        <Link className="brand" href="/" aria-label="صفحه اصلی کسبمن">
          <span className="brand-mark">ک</span>
          <span>کسبمن</span>
        </Link>
        <span className="topbar-note">پلتفرم یکپارچه مدیریت کسب‌وکار</span>
      </header>

      <section className="hero">
        <div className="eyebrow"><span className="status-dot" /> زیرساختی برای رشد هوشمند</div>
        <h1>کسب‌وکارت،<br /><span>یک قدم جلوتر.</span></h1>
        <p className="hero-copy">
          مدیریت، برنامه‌ریزی و توسعه کسب‌وکار؛ در یک پلتفرم یکپارچه،
          منعطف و آماده رشد.
        </p>
        <div className="hero-actions">
          <Link className="primary-action" href="/signup">ساخت حساب رایگان</Link>
          <Link className="secondary-action" href="/login">ورود به حساب</Link>
        </div>
        <div className="hero-orbit" aria-hidden="true">
          <div className="orbit orbit-one" />
          <div className="orbit orbit-two" />
          <div className="orbit-core">K</div>
          <span className="orbit-node node-one" />
          <span className="orbit-node node-two" />
          <span className="orbit-node node-three" />
        </div>
      </section>

      <section className="capabilities" aria-labelledby="capabilities-title">
        <div className="section-heading">
          <span className="section-kicker">KASBEMAN PLATFORM</span>
          <h2 id="capabilities-title">یک هسته، امکانات گسترده</h2>
        </div>
        <div className="capability-grid">
          {capabilities.map((item) => (
            <article className="capability" key={item.number}>
              <span className="capability-number">{item.number}</span>
              <h3>{item.title}</h3>
              <p>{item.description}</p>
            </article>
          ))}
        </div>
      </section>

      <footer className="footer">
        <span>کسبمن © {new Date().getFullYear()}</span>
        <span>ساخته‌شده برای مدیریت بهتر</span>
      </footer>
    </main>
  );
}
