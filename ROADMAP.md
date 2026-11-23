# Roadmap / ideas

- **Long-term comparison engine** ("this year vs 2018"): weight and resting HR have 10+ years of data in Garmin.
  - Overlay aligned periods (same calendar window or same length, different years) on one chart.
  - Delta stats: average, min/max, trend per period, difference vs. a chosen reference year.
  - Needs: history depth beyond the current 5 years (10 years is offered in Settings already), a compact long-term
    store (monthly aggregates are probably enough for ranges > 2 years), a period picker UI.
- More ranges beyond 1 year / 2 years once long-term data is cached.
- Optional: manual blood-pressure entry as an alternative to Apple Health.

- Not possible with the Garmin Personal API (checked its Swagger schemas and a real `dailySleep` response): minute-by-minute sleep stages / hypnogram. Only nightly totals, bed/wake times and ideal ranges are provided.
