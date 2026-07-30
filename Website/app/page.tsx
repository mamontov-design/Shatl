"use client";

import { useEffect, useRef, useState } from "react";

const GITHUB_URL = "https://github.com/mamontov-design/Shatl";
const DOWNLOAD_URL =
  "https://github.com/mamontov-design/shatl-updates/releases/latest/download/Shatl.dmg";
const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

function assetPath(path: string) {
  return `${BASE_PATH}${path}`;
}

const modes = [
  {
    id: "economical",
    name: "Экономный",
    icon: assetPath("/performance-mode-1-light.png"),
    summary:
      "Оптимален, когда важнее продлить время работы от аккумулятора, а загрузка и раздача файлов не требуют спешки. Shatl ограничивает скорость, сокращает количество соединений и бережнее расходует память и ресурсы диска.",
    values: {
      "Базовый профиль": "min_memory_usage",
      "Соединения": "24",
      "Peer list": "100 / 20",
      "Загрузка": "до 5 MiB/s",
      "Раздача": "до 2560 KiB/s",
      "DHT upload": "2048 B/s",
      LSD: "Выключен",
      "Connection speed": "3",
      "Disk queue": "256 KiB",
      "I/O потоки": "1",
      "Hashing потоки": "1",
      "Checking memory": "2 MiB",
    },
  },
  {
    id: "balanced",
    name: "Баланс",
    icon: assetPath("/performance-mode-2-light.png"),
    summary:
      "Рекомендуемый режим для повседневной и продолжительной работы — он выбран по умолчанию. Скорость не ограничивается, а сетевые, дисковые и вычислительные параметры остаются на умеренном уровне.",
    values: {
      "Базовый профиль": "default_settings",
      "Соединения": "1000",
      "Peer list": "3000 / 1000",
      "Загрузка": "Без ограничения",
      "Раздача": "Без ограничения",
      "DHT upload": "16 KiB/s",
      LSD: "Включён",
      "Connection speed": "100",
      "Disk queue": "16 MiB",
      "I/O потоки": "8",
      "Hashing потоки": "4",
      "Checking memory": "256 MiB",
    },
  },
  {
    id: "maximum",
    name: "Максимум",
    icon: assetPath("/performance-mode-3-light.png"),
    summary:
      "Подходит для Mac с запасом ресурсов — особенно при быстром интернет‑соединении и большом количестве одновременных загрузок. Shatl увеличивает количество соединений, дисковую очередь и число рабочих потоков, чтобы не сдерживать производительность.",
    values: {
      "Базовый профиль": "high_performance_seed",
      "Соединения": "5000",
      "Peer list": "Без ограничения",
      "Загрузка": "Без ограничения",
      "Раздача": "Без ограничения",
      "DHT upload": "Без ограничения",
      LSD: "Включён",
      "Connection speed": "200",
      "Disk queue": "64 MiB",
      "I/O потоки": "16",
      "Hashing потоки": "8",
      "Checking memory": "512 MiB",
    },
  },
] as const;

const comparisonRows = Object.keys(modes[0].values) as Array<
  keyof (typeof modes)[number]["values"]
>;

const smallFeatures = [
  {
    label: "01",
    title: "Открывайте как удобно",
    description:
      "Выберите .torrent‑файл в Finder или откройте magnet‑ссылку в браузере — Shatl продолжит добавление в уже запущенном приложении.",
  },
  {
    label: "02",
    title: "На семи языках",
    description:
      "Shatl доступен на английском, немецком, испанском, французском, русском, японском и упрощённом китайском.",
  },
  {
    label: "03",
    title: "Больше 90% Swift",
    description:
      "Основная логика и интерфейс Shatl написаны на Swift. По данным GitHub, Swift занимает более 90% распознанного кода репозитория.",
  },
  {
    label: "04",
    title: "В цвете вашего Mac",
    description:
      "Shatl использует выбранный в macOS акцентный цвет в элементах интерфейса и анимациях.",
  },
];

function GitHubIcon() {
  return (
    <svg
      className="button-icon"
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
    >
      <path
        fill="currentColor"
        d="M12 2C6.48 2 2 6.58 2 12.23c0 4.52 2.87 8.35 6.84 9.71.5.1.68-.22.68-.49 0-.24-.01-1.05-.01-1.91-2.78.62-3.37-1.2-3.37-1.2-.45-1.18-1.11-1.49-1.11-1.49-.91-.64.07-.63.07-.63 1 .07 1.53 1.06 1.53 1.06.89 1.56 2.34 1.11 2.91.85.09-.66.35-1.11.63-1.37-2.22-.26-4.56-1.14-4.56-5.06 0-1.12.39-2.03 1.03-2.75-.1-.26-.45-1.3.1-2.71 0 0 .84-.28 2.75 1.05A9.36 9.36 0 0 1 12 6.95c.85 0 1.69.12 2.49.34 1.91-1.33 2.75-1.05 2.75-1.05.55 1.41.2 2.45.1 2.71.64.72 1.03 1.63 1.03 2.75 0 3.93-2.34 4.8-4.57 5.06.36.32.68.94.68 1.9 0 1.37-.01 2.47-.01 2.81 0 .27.18.59.69.49A10.25 10.25 0 0 0 22 12.23C22 6.58 17.52 2 12 2Z"
      />
    </svg>
  );
}

function Brand() {
  return (
    <a className="brand" href="#top" aria-label="Shatl — к началу страницы">
      <span className="brand-mark" aria-hidden="true">
        S
      </span>
      <span>Shatl</span>
    </a>
  );
}

function Placeholder({
  label,
  detail,
  compact = false,
}: {
  label: string;
  detail: string;
  compact?: boolean;
}) {
  return (
    <div className={`placeholder ${compact ? "placeholder-compact" : ""}`}>
      <span className="placeholder-label">{label}</span>
      <span className="placeholder-detail">{detail}</span>
    </div>
  );
}

function PerformanceDialog({
  onClose,
}: {
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    const focusable = () =>
      Array.from(
        dialogRef.current?.querySelectorAll<HTMLElement>(
          'button, [href], select, [tabindex]:not([tabindex="-1"])',
        ) ?? [],
      ).filter((element) => !element.hasAttribute("disabled"));

    focusable()[0]?.focus();

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        onClose();
        return;
      }

      if (event.key !== "Tab") return;
      const elements = focusable();
      if (elements.length === 0) return;
      const first = elements[0];
      const last = elements[elements.length - 1];

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose]);

  return (
    <div className="dialog-backdrop" onMouseDown={onClose}>
      <div
        ref={dialogRef}
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="comparison-title"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="dialog-header">
          <div>
            <p className="eyebrow">Что меняется внутри</p>
            <h2 id="comparison-title">Режимы производительности.</h2>
          </div>
          <button className="button button-secondary" type="button" onClick={onClose}>
            Закрыть
          </button>
        </div>

        <div className="comparison-desktop">
          <table>
            <thead>
              <tr>
                <th scope="col">Параметр</th>
                {modes.map((mode) => (
                  <th scope="col" key={mode.id}>
                    {mode.name}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {comparisonRows.map((row) => (
                <tr key={row}>
                  <th scope="row">{row}</th>
                  {modes.map((mode) => (
                    <td key={mode.id}>{mode.values[row]}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="comparison-mobile">
          {modes.map((mode) => (
            <article className="comparison-profile" key={mode.id}>
              <h3>{mode.name}</h3>
              <p>{mode.summary}</p>
              <dl>
                {comparisonRows.map((row) => (
                  <div key={row}>
                    <dt>{row}</dt>
                    <dd>{mode.values[row]}</dd>
                  </div>
                ))}
              </dl>
            </article>
          ))}
        </div>

        <div className="glossary">
          <p>
            <strong>DHT</strong> — распределённая хеш‑таблица для поиска пиров
            без обязательного центрального трекера.
          </p>
          <p>
            <strong>LSD</strong> — обнаружение других пиров в локальной сети.
          </p>
        </div>
      </div>
    </div>
  );
}

export default function Home() {
  const heroActionsRef = useRef<HTMLDivElement>(null);
  const compareButtonRef = useRef<HTMLButtonElement>(null);
  const [showBar, setShowBar] = useState(false);
  const [showLanguageBanner, setShowLanguageBanner] = useState(true);
  const [showLanguageMenu, setShowLanguageMenu] = useState(false);
  const [showComparison, setShowComparison] = useState(false);
  const [shareStatus, setShareStatus] = useState("");

  useEffect(() => {
    if (!heroActionsRef.current) return;
    const observer = new IntersectionObserver(
      ([entry]) => setShowBar(!entry.isIntersecting),
      { threshold: 0.25 },
    );
    observer.observe(heroActionsRef.current);
    return () => observer.disconnect();
  }, []);

  async function shareDownload() {
    const shareData = {
      title: "Скачать Shatl",
      text: "Shatl — лёгкий торрент‑клиент для Mac.",
      url: DOWNLOAD_URL,
    };

    try {
      if (navigator.share) {
        await navigator.share(shareData);
        setShareStatus("");
      } else {
        await navigator.clipboard.writeText(DOWNLOAD_URL);
        setShareStatus("Ссылка скопирована");
      }
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") return;
      setShareStatus("Не удалось поделиться ссылкой");
    }
  }

  function closeComparison() {
    setShowComparison(false);
    requestAnimationFrame(() => compareButtonRef.current?.focus());
  }

  return (
    <>
      <a className="skip-link" href="#content">
        Перейти к содержимому
      </a>

      {showLanguageBanner && (
        <aside className="language-banner" aria-label="Язык страницы">
          <div className="container language-banner-inner">
            <span>
              Язык страницы: <strong>Русский</strong>
            </span>
            <div className="language-actions">
              <button
                type="button"
                onClick={() => setShowLanguageMenu((value) => !value)}
                aria-expanded={showLanguageMenu}
              >
                Изменить
              </button>
              <button type="button" onClick={() => setShowLanguageBanner(false)}>
                Закрыть
              </button>
            </div>
            {showLanguageMenu && (
              <div className="language-menu" aria-label="Доступные языки">
                <strong>Русский</strong>
                <span>English</span>
                <span>Deutsch</span>
                <span>Español</span>
                <span>Français</span>
                <span>日本語</span>
                <span>简体中文</span>
              </div>
            )}
          </div>
        </aside>
      )}

      {showBar && (
        <header className="cta-bar">
          <div className="container cta-bar-inner">
            <Brand />
            <div className="cta-bar-actions">
              <span className="service-note">macOS 27+ · Apple Silicon</span>
              <a className="button button-ghost" href={GITHUB_URL}>
                <GitHubIcon />
                GitHub
              </a>
              <a className="button button-primary" href={DOWNLOAD_URL}>
                Скачать
              </a>
            </div>
          </div>
        </header>
      )}

      <main id="content">
        <section className="hero section section-01-hero" id="top">
          <div className="container hero-grid">
            <div className="hero-copy">
              <img
                className="app-icon-placeholder"
                src={assetPath("/hero-logomark-light.png")}
                alt="Иконка Shatl"
                width="168"
                height="168"
                decoding="async"
                fetchPriority="high"
              />
              <h1>Встречайте Shatl.</h1>
              <p className="hero-description">
                Лёгкий торрент‑клиент для Mac на базе libtorrent с открытым
                исходным кодом. Выбирайте нужные файлы до начала загрузки,
                управляйте нагрузкой на Mac и следите за прогрессом
                без лишнего визуального шума.
              </p>
              <div className="hero-actions" ref={heroActionsRef}>
                <a className="button button-primary button-large" href={DOWNLOAD_URL}>
                  Скачать Shatl
                </a>
                <a className="button button-secondary button-large" href={GITHUB_URL}>
                  <GitHubIcon />
                  GitHub
                </a>
              </div>
              <div className="mobile-share-wrap">
                <button
                  className="button button-secondary"
                  type="button"
                  onClick={shareDownload}
                >
                  Отправить ссылку на Mac
                </button>
                <span aria-live="polite">{shareStatus}</span>
              </div>
              <div className="requirements requirements-hero">
                <span>macOS 27 или новее</span>
                <span>Только Apple Silicon</span>
              </div>
              <p className="launch-note">Требуется разрешение при первом запуске</p>
            </div>

            <div className="demo-frame" aria-label="Заглушка демонстрационного видео">
              <Placeholder
                label="Демонстрационное видео"
                detail="Окно Shatl · 60 FPS · Retina"
              />
              <div className="demo-controls">
                <button type="button" aria-label="Поставить демонстрацию на паузу">
                  Пауза
                </button>
                <span>00:00 / 00:20</span>
              </div>
            </div>
          </div>
        </section>

        <section className="section feature-section section-02-control">
          <div className="container split-layout">
            <div className="section-copy">
              <p className="eyebrow">Осознанный старт</p>
              <h2>Контроль до начала загрузки.</h2>
              <p>
                Добавьте .torrent‑файл или вставьте magnet‑ссылку. Shatl получит
                метаданные и покажет содержимое раздачи до начала загрузки.
                Выберите нужные файлы и папки, место сохранения, псевдоним
                и нужно ли остановить раздачу после завершения. Перед стартом
                вы увидите объём выбранных файлов и доступное место на диске.
              </p>
            </div>
            <div className="feature-media">
              <div className="feature-frame">
                <img
                  className="feature-image"
                  src={assetPath("/AddTorrentScreenLight.png")}
                  alt="Экран Shatl для выбора файлов перед началом загрузки"
                  width="936"
                  height="942"
                  loading="lazy"
                  decoding="async"
                />
              </div>
            </div>
          </div>
        </section>

        <section className="section performance-section section-03-performance">
          <div className="container">
            <div className="section-heading">
              <p className="eyebrow">3 режима производительности</p>
              <h2>От экономии заряда до максимальной скорости.</h2>
              <p>
                Мы понимаем, что одинаковые настройки подходят не всем
                пользователям Mac. Поэтому предлагаем выбрать, как Shatl
                распоряжается сетью, памятью и ресурсами компьютера. Один режим
                меняет сразу весь набор параметров движка — настраивать каждый
                вручную не придётся.
              </p>
            </div>
            <div className="mode-grid">
              {modes.map((mode) => (
                <article className="mode-card" key={mode.id}>
                  <div className="mode-card-header">
                    <img
                      className="mode-icon"
                      src={mode.icon}
                      alt=""
                      width="96"
                      height="96"
                      loading="lazy"
                      decoding="async"
                    />
                    <span className="mode-index">
                      {String(modes.indexOf(mode) + 1).padStart(2, "0")}
                    </span>
                  </div>
                  <h3>{mode.name}</h3>
                  <p>{mode.summary}</p>
                </article>
              ))}
            </div>
            <button
              ref={compareButtonRef}
              className="button button-secondary"
              type="button"
              onClick={() => setShowComparison(true)}
            >
              Сравнить режимы
            </button>
          </div>
        </section>

        <section className="section feature-section section-04-metrics">
          <div className="container split-layout split-layout-reverse">
            <Placeholder
              label="Сравнение интерфейса"
              detail="Упрощённые и подробные метрики"
            />
            <div className="section-copy">
              <p className="eyebrow">Метрики под ваш взгляд</p>
              <h2>Данные — проще или точнее.</h2>
              <p>
                В упрощённом режиме Shatl округляет скорость, объём данных
                и оставшееся время, чтобы карточки было легче читать. Подробный
                режим показывает более точные значения. Прогресс, количество
                сидов и пиров и работа загрузки не меняются — меняется только
                представление данных.
              </p>
            </div>
          </div>
        </section>

        <section className="section compact-features section-05-compact">
          <div className="container">
            <div className="small-feature-grid">
              {smallFeatures.map((feature) => (
                <article className="small-feature-card" key={feature.title}>
                  <span>{feature.label}</span>
                  <h3>{feature.title}</h3>
                  <p>{feature.description}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="section trust-section section-06-trust">
          <div className="container trust-grid">
            <article className="trust-card">
              <p className="eyebrow">Телеметрия по согласию</p>
              <h2>Приватность, которую можно проверить.</h2>
              <p className="trust-lead">
                Shatl не отправляет сведения о торрентах, magnet‑ссылках, именах
                файлов или путях.
              </p>
              <p>
                Анонимная статистика отправляется только с вашего разрешения
                и не чаще одного раза в неделю. Перед отправкой можно посмотреть
                точный состав данных: количество запусков, версию приложения,
                язык интерфейса и случайный идентификатор установки.
              </p>
            </article>
            <article className="trust-card">
              <p className="eyebrow">Лицензия GPL‑3.0‑only</p>
              <h2>Открытый код. Прозрачные обновления.</h2>
              <p>
                Исходный код Shatl опубликован на GitHub под лицензией
                GPL‑3.0‑only, а в качестве торрент‑движка используется
                libtorrent. История выпусков и файлы обновлений доступны
                публично.
              </p>
              <a className="text-link" href={GITHUB_URL}>
                Открыть репозиторий
              </a>
            </article>
          </div>
        </section>

        <section className="section final-cta section-07-final">
          <div className="container final-cta-inner">
            <div>
              <p className="eyebrow">Ваш новый торрент‑клиент</p>
              <h2>Попробуйте Shatl на своём Mac.</h2>
              <p>
                Скачайте образ, перенесите Shatl в папку «Программы» и разрешите
                первый запуск в настройках конфиденциальности macOS.
              </p>
            </div>
            <div className="final-actions">
              <a className="button button-primary button-large" href={DOWNLOAD_URL}>
                Скачать Shatl
              </a>
              <a className="button button-secondary button-large" href={GITHUB_URL}>
                <GitHubIcon />
                Открыть на GitHub
              </a>
              <button
                className="button button-secondary mobile-share"
                type="button"
                onClick={shareDownload}
              >
                Отправить ссылку на Mac
              </button>
            </div>
            <div className="requirements">
              <span>macOS 27 или новее</span>
              <span>Только Apple Silicon</span>
              <span>Требуется разрешение при первом запуске</span>
            </div>
          </div>
        </section>
      </main>

      <footer className="footer">
        <div className="container footer-inner">
          <Brand />
          <div className="footer-links">
            <span>Русский</span>
            <a href={GITHUB_URL}>GitHub</a>
            <span>GPL‑3.0‑only</span>
          </div>
        </div>
      </footer>

      {showComparison && <PerformanceDialog onClose={closeComparison} />}
    </>
  );
}
