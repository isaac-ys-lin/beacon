const { useMemo, useState } = React;

const deviceGroups = [
  {
    id: "desk",
    devices: [
      { id: "mac", name: "Isaac's MacBook Pro", detail: "Local Mac · charging", kind: "mac", percent: 88, charging: true },
      { id: "keyboard", name: "Magic Keyboard", detail: "Bluetooth · fresh", kind: "keyboard", percent: 87 },
      { id: "trackpad", name: "Magic Trackpad", detail: "Bluetooth · fresh", kind: "trackpad", percent: 74 },
      { id: "mouse", name: "Magic Mouse", detail: "Bluetooth · seen 2m ago", kind: "mouse", percent: 41, stale: true }
    ]
  },
  {
    id: "mobile",
    devices: [
      { id: "iphone", name: "Isaac's iPhone", detail: "iCloud · charging", kind: "phone", percent: 70, charging: true },
      { id: "watch", name: "Apple Watch", detail: "Watch relay · low", kind: "watch", percent: 18, low: true },
      {
        id: "airpods",
        name: "AirPods Pro 2",
        detail: "Nearby · component batteries",
        kind: "airpods",
        percent: 86,
        components: [
          { label: "Case", percent: 88 },
          { label: "L", percent: 86 },
          { label: "R", percent: 82 }
        ]
      },
      { id: "ipad", name: "iPad mini", detail: "iCloud · fresh", kind: "phone", percent: 100, charging: true }
    ]
  }
];

function Glyph({ kind }) {
  return (
    <span className="device-icon" aria-hidden="true">
      <span className={`device-glyph ${kind}`}></span>
    </span>
  );
}

function Battery({ percent, charging, mini = false }) {
  const levelClass = percent <= 20 ? "low" : percent <= 45 ? "warn" : "";
  const width = mini ? Math.max(2, percent * 0.16) : Math.max(4, percent * 0.26);
  if (mini) {
    return (
      <span className="mini-battery" aria-label={`${percent}%`}>
        <span className="mini-fill" style={{ width }}></span>
      </span>
    );
  }
  return (
    <span className="battery" aria-label={`${percent}%`}>
      <span className={`battery-fill ${levelClass}`} style={{ width }}></span>
      {charging ? <span className="bolt">⌁</span> : null}
    </span>
  );
}

function DeviceRow({ device, selected, onSelect }) {
  const percentClass = device.low ? "low" : device.stale ? "stale" : "";
  return (
    <div className={`row ${selected ? "selected" : ""}`} onClick={() => onSelect(device)} role="button" tabIndex="0">
      <Glyph kind={device.kind} />
      <div className="device-meta">
        <div className="device-name">{device.name}</div>
        <div className="device-detail">{device.detail}</div>
      </div>
      <div className="battery-cluster">
        <span className={`percent ${percentClass}`}>{device.percent}%</span>
        <Battery percent={device.percent} charging={device.charging} />
      </div>
      {device.components ? (
        <div className="chips">
          {device.components.map((component) => (
            <span className="chip" key={component.label}>
              {component.label}
              <span>{component.percent}%</span>
              <Battery percent={component.percent} mini />
            </span>
          ))}
        </div>
      ) : null}
    </div>
  );
}

function DeviceList({ selectedId, onSelect }) {
  return (
    <>
      {deviceGroups.map((group) => (
        <div className="section-card" key={group.id}>
          {group.devices.map((device) => (
            <DeviceRow
              key={device.id}
              device={device}
              selected={selectedId === device.id}
              onSelect={onSelect}
            />
          ))}
        </div>
      ))}
    </>
  );
}

function MenuScreen({ selectedDevice, setSelectedDevice }) {
  return (
    <>
      <DeviceList selectedId={selectedDevice.id} onSelect={setSelectedDevice} />
      <div className="detail-drawer">
        <div className="detail-title">
          <span>{selectedDevice.name}</span>
          <span className="status-pill"><span className={`dot ${selectedDevice.low || selectedDevice.stale ? "warn" : ""}`}></span>{selectedDevice.low ? "Low" : selectedDevice.stale ? "Stale" : "Fresh"}</span>
        </div>
        <div className="action-row">
          <button className="secondary-action">Alert</button>
          <button className="secondary-action">Pin</button>
          <button className="secondary-action">Details</button>
        </div>
      </div>
    </>
  );
}

function HudScreen() {
  return (
    <div className="hud">
      <div>
        <h2>AirPods Pro 2</h2>
        <p>Click to connect</p>
      </div>
      <div className="airpods-art" aria-hidden="true">
        <span className="pod left"></span>
        <span className="pod right"></span>
      </div>
      <div className="hud-batteries">
        <div className="hud-meter"><Battery percent={88} mini />Case 88%</div>
        <div className="hud-meter"><Battery percent={86} mini />Left 86%</div>
        <div className="hud-meter"><Battery percent={82} mini />Right 82%</div>
      </div>
      <button className="primary-action">Connect to This Mac</button>
    </div>
  );
}

function AlertsScreen() {
  return (
    <div className="panel-stack">
      <div className="alert-panel">
        <div className="field-row">
          <div className="field-copy">
            <strong>Low battery alerts</strong>
            <span>Notify before devices become unavailable.</span>
          </div>
          <button className="switch" aria-label="Low battery alerts on"></button>
        </div>
        <div className="field-row">
          <div className="field-copy">
            <strong>Threshold</strong>
            <span>Default for new devices</span>
          </div>
          <input className="slider" type="range" min="5" max="50" defaultValue="20" aria-label="Alert threshold" />
        </div>
      </div>
      <div className="section-card">
        <DeviceRow device={{ id: "watch-alert", name: "Apple Watch", detail: "Preview alert · 18% remaining", kind: "watch", percent: 18, low: true }} selected={false} onSelect={() => {}} />
      </div>
    </div>
  );
}

function SettingsScreen() {
  return (
    <div className="settings-panel">
      <div className="panel-stack">
        <div className="field-row">
          <div className="field-copy">
            <strong>Refresh nearby devices</strong>
            <span>Manual refresh keeps the menu quiet.</span>
          </div>
          <button className="secondary-action">Refresh</button>
        </div>
        <div className="field-row">
          <div className="field-copy">
            <strong>iCloud sync</strong>
            <span>Last successful read 24 seconds ago.</span>
          </div>
          <span className="status-pill"><span className="dot"></span>Healthy</span>
        </div>
        <div className="field-row">
          <div className="field-copy">
            <strong>Show stale data</strong>
            <span>Keep devices visible with clear age labels.</span>
          </div>
          <button className="switch" aria-label="Show stale data on"></button>
        </div>
      </div>
    </div>
  );
}

function Header({ activeScreen, setActiveScreen }) {
  const isSettings = activeScreen === "settings";
  return (
    <div className="header">
      <div>
        <h1 className="header-title">Your Devices</h1>
        <div className="header-subtitle">Updated now · 8 devices nearby</div>
      </div>
      <div className="toolbar">
        <button className="icon-button" title="Refresh" aria-label="Refresh">↻</button>
        <button
          className="icon-button"
          title={isSettings ? "Close settings" : "Settings"}
          aria-label={isSettings ? "Close settings" : "Settings"}
          onClick={() => setActiveScreen(isSettings ? "menu" : "settings")}
        >
          {isSettings ? "×" : "⚙"}
        </button>
      </div>
    </div>
  );
}

function Popover({ variant, activeScreen, setActiveScreen, selectedDevice, setSelectedDevice }) {
  return (
    <div className={`popover variant-${variant}`} data-screen-label="BatteryHub Popover">
      <Header activeScreen={activeScreen} setActiveScreen={setActiveScreen} />
      <div className={`screen ${activeScreen === "menu" ? "active" : ""}`}>
        <MenuScreen selectedDevice={selectedDevice} setSelectedDevice={setSelectedDevice} />
      </div>
      <div className={`screen ${activeScreen === "hud" ? "active" : ""}`}>
        <HudScreen />
      </div>
      <div className={`screen ${activeScreen === "alerts" ? "active" : ""}`}>
        <AlertsScreen />
      </div>
      <div className={`screen ${activeScreen === "settings" ? "active" : ""}`}>
        <SettingsScreen />
      </div>
      <div className="footer">
        <span className="status-pill"><span className="dot warn"></span>Alerts below 20%</span>
        <span>Best-effort sync</span>
      </div>
    </div>
  );
}

function Controls({ theme, setTheme, density, setDensity, variant, setVariant, activeScreen, setActiveScreen }) {
  const screenOptions = [
    ["menu", "Menu"],
    ["hud", "HUD"],
    ["alerts", "Alerts"],
    ["settings", "Settings"]
  ];
  return (
    <aside className="side-panel">
      <div>
        <h1>BatteryHub UIUX</h1>
        <p>AirBuddy-level polish translated into a quieter native utility: glanceable rows, spatial grouping, and contextual controls.</p>
      </div>
      <div className="notes">
        <div className="control-group">
          <div className="control-label">Screen</div>
          <div className="segmented">
            {screenOptions.map(([id, label]) => (
              <button key={id} className={activeScreen === id ? "active" : ""} onClick={() => setActiveScreen(id)}>{label}</button>
            ))}
          </div>
        </div>
        <div className="control-group">
          <div className="control-label">Visual Variant</div>
          <div className="segmented">
            {["native", "airbuddy", "compact"].map((id) => (
              <button key={id} className={variant === id ? "active" : ""} onClick={() => setVariant(id)}>{id}</button>
            ))}
          </div>
        </div>
        <div className="control-group">
          <div className="control-label">Theme</div>
          <div className="segmented">
            {["light", "dark"].map((id) => (
              <button key={id} className={theme === id ? "active" : ""} onClick={() => setTheme(id)}>{id}</button>
            ))}
          </div>
        </div>
        <div className="control-group">
          <div className="control-label">Density</div>
          <div className="segmented">
            {["regular", "compact"].map((id) => (
              <button key={id} className={density === id ? "active" : ""} onClick={() => setDensity(id)}>{id}</button>
            ))}
          </div>
        </div>
        <div className="note">
          <strong>UX Priority</strong>
          <span>Use the popover as the daily surface. Keep detailed controls one click away instead of turning the menu into a settings window.</span>
        </div>
        <div className="note">
          <strong>Implementation Fit</strong>
          <span>The structure maps cleanly to the current SwiftUI grouping model and `DesignTokens.swift`; most changes can be view-layer only.</span>
        </div>
      </div>
    </aside>
  );
}

function ReferenceStrip() {
  return (
    <div className="reference-strip" aria-label="AirBuddy public screenshot references">
      <div className="reference-card">
        <img src="assets/airbuddy-platter-large.png" alt="AirBuddy AirPods status window reference" />
        <span>AirBuddy HUD reference</span>
      </div>
      <div className="reference-card">
        <img src="assets/airbuddy-menu-bar-light.png" alt="AirBuddy menu bar reference" />
        <span>AirBuddy menu reference</span>
      </div>
    </div>
  );
}

function App() {
  const [theme, setTheme] = useState("light");
  const [density, setDensity] = useState("regular");
  const [variant, setVariant] = useState("native");
  const [activeScreen, setActiveScreen] = useState("menu");
  const defaultSelected = useMemo(() => deviceGroups[1].devices[2], []);
  const [selectedDevice, setSelectedDevice] = useState(defaultSelected);

  return (
    <main className="desktop" data-theme={theme} data-density={density}>
      <div className="menu-bar">
        <span className="apple-mark" aria-hidden="true"></span>
        <span className="menu-title">BatteryHub</span>
        <span>File</span>
        <span>Edit</span>
        <span>View</span>
        <span className="menu-spacer"></span>
        <span className="menu-status"><Battery percent={88} mini /> 88%</span>
        <span>Thu 10:28</span>
      </div>
      <div className="workspace">
        <section className="stage">
          <div className="popover-anchor"></div>
          <Popover
            variant={variant}
            activeScreen={activeScreen}
            setActiveScreen={setActiveScreen}
            selectedDevice={selectedDevice}
            setSelectedDevice={setSelectedDevice}
          />
          <ReferenceStrip />
        </section>
        <Controls
          theme={theme}
          setTheme={setTheme}
          density={density}
          setDensity={setDensity}
          variant={variant}
          setVariant={setVariant}
          activeScreen={activeScreen}
          setActiveScreen={setActiveScreen}
        />
      </div>
    </main>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
