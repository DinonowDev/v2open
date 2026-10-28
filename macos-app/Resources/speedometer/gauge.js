(() => {
  const VALUES = [0, 5, 15, 30, 60, 120, 200, 300];
  const LAST = VALUES.length - 1;
  const STOPS = VALUES.map((value, i) => [value, i / LAST]);
  const LABEL_INSET = 0.02;

  const START_ANGLE = 210;
  const END_ANGLE = -30;
  const SWEEP = START_ANGLE - END_ANGLE;

  const el = document.getElementById("chart");
  const chart = echarts.init(el, null, { renderer: "svg" });

  const state = {
    mbps: 0,
    idle: true,
    running: false,
    phase: "download",
    go: "GO",
    unit: "Mbps",
  };

  function isBytes() {
    return state.unit === "MB/s";
  }

  function toDisplay(mbps) {
    return isBytes() ? mbps / 8 : mbps;
  }

  function formatTick(mbps) {
    const v = toDisplay(mbps);
    if (v === 0) return "0";
    if (v >= 10) return (Math.round(v * 10) / 10).toString();
    const text = v.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
    return text;
  }

  function formatValue(mbps) {
    return toDisplay(mbps).toFixed(2);
  }

  function mbpsToAxis(mbps) {
    const m = Math.min(Math.max(mbps, 0), 300);
    for (let i = 1; i < STOPS.length; i += 1) {
      const [loV, loT] = STOPS[i - 1];
      const [hiV, hiT] = STOPS[i];
      if (m <= hiV) {
        const t = hiV === loV ? 0 : (m - loV) / (hiV - loV);
        return (loT + t * (hiT - loT)) * 100;
      }
    }
    return 100;
  }

  function accent() {
    return state.phase === "upload" ? "#A78BF0" : "#22D3EE";
  }

  function angleOf(t) {
    return START_ANGLE - t * SWEEP;
  }

  function polar(cx, cy, r, deg) {
    const rad = (deg * Math.PI) / 180;
    return [cx + r * Math.cos(rad), cy - r * Math.sin(rad)];
  }

  function gaugeLayout() {
    const w = el.clientWidth || 320;
    const h = el.clientHeight || 240;
    const cx = w * 0.5;
    const cy = h * 0.58;
    const outer = 0.92 * Math.min(w, h) * 0.5;
    const labelR = outer - 29;
    return { w, h, cx, cy, outer, labelR };
  }

  function labelGraphics() {
    const { cx, cy, labelR } = gaugeLayout();
    return STOPS.map(([mbps, t], i) => {
      const place = LABEL_INSET + t * (1 - LABEL_INSET * 2);
      const [x, y] = polar(cx, cy, labelR, angleOf(place));
      return {
        type: "text",
        id: "tick-" + i,
        x,
        y,
        z: 100,
        zlevel: 1,
        style: {
          text: formatTick(mbps),
          fill: "rgba(232,238,247,0.88)",
          font: "600 11px Inter, -apple-system, sans-serif",
          align: "center",
          verticalAlign: "middle",
        },
        silent: true,
      };
    });
  }

  function optionForSize() {
    const color = accent();
    const axis = state.idle ? 0 : mbpsToAxis(state.mbps);
    const showValue = !state.idle && (state.mbps > 0 || !state.running);
    const waiting = state.running && state.mbps <= 0;

    return {
      animation: true,
      animationDuration: 200,
      animationDurationUpdate: 140,
      animationEasing: "cubicOut",
      animationEasingUpdate: "cubicOut",
      graphic: labelGraphics(),
      series: [
        {
          type: "gauge",
          center: ["50%", "58%"],
          radius: "92%",
          startAngle: START_ANGLE,
          endAngle: END_ANGLE,
          min: 0,
          max: 100,
          splitNumber: 8,
          silent: false,
          axisLine: {
            roundCap: true,
            lineStyle: {
              width: 14,
              color: [[1, "#2A3344"]],
            },
          },
          progress: {
            show: !state.idle && axis > 0.15,
            roundCap: true,
            width: 14,
            itemStyle: { color },
          },
          pointer: {
            show: !state.idle,
            icon: "path://M 0 -92 L 5.2 8 L 0 2 L -5.2 8 Z",
            length: "68%",
            width: 10,
            offsetCenter: [0, 0],
            itemStyle: {
              color: new echarts.graphic.LinearGradient(0, 1, 0, 0, [
                { offset: 0, color: "rgba(255,255,255,0.18)" },
                { offset: 1, color: "rgba(255,255,255,0.95)" },
              ]),
            },
          },
          anchor: {
            show: !state.idle,
            showAbove: true,
            size: 8,
            itemStyle: { color: "rgba(255,255,255,0.9)" },
          },
          axisTick: { show: false },
          splitLine: { show: false },
          axisLabel: { show: false },
          title: {
            show: showValue,
            offsetCenter: [0, "48%"],
            color,
            fontSize: 11,
            fontWeight: 600,
            fontFamily: "Inter, -apple-system, sans-serif",
          },
          detail: {
            show: !state.idle,
            valueAnimation: false,
            offsetCenter: [0, "32%"],
            formatter: () => {
              if (waiting) return "···";
              return formatValue(state.mbps);
            },
            color: "#fff",
            fontSize: 18,
            fontWeight: 700,
            fontFamily: "Inter, -apple-system, sans-serif",
          },
          data: [{
            value: axis,
            name: (state.phase === "upload" ? "↑  " : "↓  ") + (state.unit || "Mbps"),
          }],
        },
      ],
    };
  }

  function render() {
    chart.setOption(optionForSize(), { notMerge: true });
  }

  window.gaugeSet = function gaugeSet(next) {
    Object.assign(state, next || {});
    render();
  };

  window.addEventListener("resize", () => {
    chart.resize();
    render();
  });

  render();
})();
