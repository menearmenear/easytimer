import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// EasyTimer: a bar label plus a keyboard/mouse popup for a countdown or focus
// cycle. Every duration, glyph, label, color and behaviour toggle lives in the
// widget's shell.json entry, so it can be edited here or through
// `omarchy bar set menearmenear.easytimer <key> <value>`.
//
// Runtime state is shared in ~/.local/state/omarchy/easytimer.json so the bar
// instances on every monitor show the same clock. The primary-screen instance
// ("leader") alone owns the notification and chime.
Panel {
  id: root
  moduleName: "menearmenear.easytimer"
  ipcTarget: "menearmenear.easytimer"
  manageIpc: false

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  // ---- Theme --------------------------------------------------------------
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string ff: bar ? bar.fontFamily : Style.font.family

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/easytimer.json"
  readonly property string chimePath: "/usr/share/sounds/freedesktop/stereo/complete.oga"

  // ---- Settings -----------------------------------------------------------
  readonly property var config: Model.normalizeSettings(settings)

  function saveSettings(patch) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    var merged = Model.normalizeSettings(entry)
    for (var k in patch) merged[k] = patch[k]
    merged = Model.normalizeSettings(merged)
    for (var m in merged) entry[m] = merged[m]

    // React on this click; the shell.json write echoes the same value back.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setSetting(key, value) {
    var patch = {}
    patch[key] = value
    saveSettings(patch)
  }

  function toggleSetting(key) { setSetting(key, !config[key]) }

  function adjustSetting(key, delta) {
    var next = Model.clampSetting(key, config[key] + delta)
    if (next !== config[key]) setSetting(key, next)
  }

  function adjustPhaseMinutes(delta) {
    var key = state.phase === "focus" ? "focusMinutes"
      : state.phase === "break" ? "breakMinutes" : "longBreakMinutes"
    adjustSetting(key, delta)
  }

  // ---- Runtime state ------------------------------------------------------
  property var state: Model.initialState(config)
  property real now: Date.now()
  property bool settingsOpen: false
  property real wheelAccumulator: 0

  readonly property int remaining: Model.remainingMs(state, config, now)
  readonly property real progress: Model.progress(state, config, now)
  readonly property bool running: state.status === "running"
  readonly property bool paused: state.status === "paused"
  readonly property bool ready: state.status === "ready"
  readonly property string phaseKey: Model.phaseKey(state.phase)
  readonly property string phaseTitle: strings.t("panel.phase." + phaseKey)
  readonly property string statusTitle: strings.t("panel.status." + state.status)
  readonly property string barLabel: Model.barText(state, config, now)
  readonly property var dots: Model.roundsDots(state, config)

  readonly property var hostWindow: QsWindow.window
  readonly property bool isLeader: {
    var screens = Quickshell.screens
    if (!hostWindow || !hostWindow.screen || screens.length === 0) return true
    return hostWindow.screen.name === screens[0].name
  }

  readonly property color buttonForeground: state.phase === "focus"
    ? (config.focusColor !== "" ? config.focusColor : fg)
    : (config.breakColor !== "" ? config.breakColor : fg)
  readonly property color buttonUrgent: config.doneColor !== "" ? config.doneColor : urgent

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.state = Model.parseState(text(), root.config)
    onLoadFailed: root.state = Model.initialState(root.config)
  }

  function commit(next) {
    root.now = Date.now()
    root.state = next
    stateFile.setText(Model.serializeState(next, root.now))
  }

  function startTimer() { commit(Model.start(state, config, Date.now())) }
  function pauseTimer() { commit(Model.pause(state, Date.now())) }
  function toggleTimer() { commit(Model.togglePause(state, config, Date.now())) }
  function resetTimer() { commit(Model.reset(state, config)) }
  function skipPhase() { commit(Model.skip(state, config, Date.now())) }

  function finishPhase() {
    var previousPhase = state.phase
    var next = Model.finish(state, config, Date.now())
    commit(next)
    if (!isLeader) return

    var note = Model.notification(previousPhase, next, config)
    var nextName = strings.t("panel.phase." + note.nextPhase)
    var title = strings.t("notify." + note.kind + ".title")
    var body = strings.t("notify." + note.kind + ".body." + (note.auto ? "auto" : "manual"))
      .arg(nextName).arg(note.minutes)
    if (config.notifications)
      Util.execArgv(["omarchy-notification-send", "-g", note.glyph, title, body])
    if (config.sound) chimeDelay.restart()
  }

  Timer {
    id: chimeDelay
    interval: 250
    onTriggered: Util.execArgv(["mpv", "--no-video", "--no-terminal", "--really-quiet",
      "--volume=" + root.config.soundVolume, root.chimePath])
  }

  function tick() {
    root.now = Date.now()
    if (isLeader && Model.isExpired(state, now)) finishPhase()
  }

  Timer {
    interval: 1000
    running: root.running || root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  Component.onCompleted: {
    stateFile.reload()
    tick()
  }

  onOpenedChanged: if (!opened) settingsOpen = false

  // ---- IPC: omarchy-shell menearmenear.easytimer <method> ------------------
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function start(): void { root.startTimer() }
    function pause(): void { root.pauseTimer() }
    function startPause(): void { root.toggleTimer() }
    function reset(): void { root.resetTimer() }
    function skip(): void { root.skipPhase() }
    function settingsToggle(): void { root.open(); root.settingsOpen = true }
    function status(): string {
      return JSON.stringify({ state: root.state, settings: root.config })
    }
  }

  // Reusable labeled input for the appearance section.
  component LabelledField: Column {
    id: field
    property string labelText: ""
    property string fieldText: ""
    property string placeholderText: ""
    readonly property bool editing: input.activeFocus
    signal committed(string value)

    width: parent.width
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: field.labelText
      color: Qt.darker(root.fg, 1.4)
      font.family: root.ff
      font.pixelSize: Style.font.bodySmall
    }

    TextField {
      id: input
      width: parent.width
      text: field.fieldText
      placeholderText: field.placeholderText
      foreground: root.fg
      accent: Color.accent
      onEditingFinished: field.committed(text)
      onActiveFocusChanged: if (activeFocus) selectAll()
    }
  }

  readonly property bool editing:
    iconFocusField.editing || iconBreakField.editing || iconPausedField.editing
    || labelField.editing || breakLabelField.editing
    || focusColorField.editing || breakColorField.editing || doneColorField.editing

  // ---- Bar widget ---------------------------------------------------------
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    foreground: root.buttonForeground
    activeColor: root.buttonUrgent
    active: root.ready
    dimmed: root.paused
    horizontalMargin: config.showIcon && config.barFormat !== "icon" ? 8.5 : 6.5
    centerFigures: config.barFormat !== "icon"
    tooltipText: root.ready
      ? strings.t("panel.status.ready")
      : root.phaseTitle + " · " + root.statusTitle + " · "
        + strings.t("panel.left").arg(Model.formatTime(root.remaining, config.timeFormat))

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleTimer()
      else if (b === Qt.MiddleButton) root.resetTimer()
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0) root.adjustPhaseMinutes(wheel.steps)
    }
  }

  // ---- Popup --------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(1080))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onActivateRequested: root.toggleTimer()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "p") root.toggleTimer()
        else if (t === "r") root.resetTimer()
        else if (t === "s") root.skipPhase()
        else if (t === "," || t === ".") root.settingsOpen = !root.settingsOpen
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: panelColumn
          width: parent.width
          spacing: Style.space(12)

          // Hero ------------------------------------------------------------
          PanelHero {
            width: parent.width
            title: strings.t("panel.title")
            meta: root.phaseTitle + " · " + root.statusTitle
            detail: strings.t("panel.round")
              .arg(Math.min(root.state.roundsDone + (root.state.phase === "focus" ? 1 : 0), root.config.roundsBeforeLongBreak))
              .arg(root.config.roundsBeforeLongBreak)
            foreground: root.fg
            fontFamily: root.ff
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: Model.glyph(root.state, root.config)
                color: root.ready ? root.buttonUrgent : root.buttonForeground
                font.family: root.ff
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                iconText: "󰅖"
                tooltipText: strings.t("panel.button.close")
                foreground: root.fg
                hoverColor: root.urgent
                fontFamily: root.ff
                onClicked: root.close()
              }
            }
          }

          // Countdown -------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: Model.formatTime(root.remaining, root.config.timeFormat)
              color: root.ready ? root.buttonUrgent : root.fg
              opacity: root.paused ? 0.55 : 1
              font.family: root.ff
              font.pixelSize: 54
              font.bold: true
              font.letterSpacing: -1
              Behavior on color { ColorAnimation { duration: 160 } }
              Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            Rectangle {
              width: parent.width
              height: Style.space(4)
              radius: Style.cornerRadius > 0 ? height / 2 : 0
              color: Style.selectedFillFor(root.fg, Color.accent)

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.ready ? parent.width : parent.width * root.progress
                radius: parent.radius
                color: root.ready ? root.buttonUrgent : Color.accent
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.Linear } }
              }
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(8)
              Repeater {
                model: root.dots
                Rectangle {
                  width: Style.space(10)
                  height: Style.space(10)
                  radius: Style.cornerRadius > 0 ? width / 2 : 0
                  color: modelData.done ? root.fg : (modelData.current ? Color.accent : "transparent")
                  border.width: modelData.done || modelData.current ? 0 : 1
                  border.color: Util.alpha(root.fg, 0.4)
                  Behavior on color { ColorAnimation { duration: 160 } }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.ready ? strings.t("panel.status.ready")
                : root.running
                  ? strings.t("panel.endsAt").arg(Qt.formatTime(new Date(root.state.endAt), "HH:mm"))
                  : strings.t("panel.left").arg(Model.formatTime(root.remaining, root.config.timeFormat))
              color: Qt.darker(root.fg, 1.4)
              font.family: root.ff
              font.pixelSize: Style.font.caption
              Behavior on color { ColorAnimation { duration: 160 } }
            }
          }

          // Controls --------------------------------------------------------
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacing.md

            Button {
              bordered: true
              selected: true
              iconText: root.running ? "󰏤" : "󰐊"
              text: root.running ? strings.t("panel.button.pause")
                : root.paused ? strings.t("panel.button.resume")
                : strings.t("panel.button.start")
              foreground: root.fg
              fontFamily: root.ff
              onClicked: root.toggleTimer()
            }

            Button {
              bordered: true
              iconText: "󰜉"
              text: strings.t("panel.button.reset")
              foreground: root.fg
              fontFamily: root.ff
              onClicked: root.resetTimer()
            }

            Button {
              bordered: true
              iconText: "󰒭"
              text: strings.t("panel.button.skip")
              foreground: root.fg
              fontFamily: root.ff
              onClicked: root.skipPhase()
            }
          }

          // Settings disclosure --------------------------------------------
          CursorSurface {
            width: parent.width
            height: Style.spacing.popupRowHeight + Style.space(4)
            foreground: root.fg

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.settingsOpen = !root.settingsOpen
            }

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Text {
                textFormat: Text.PlainText
                text: "󰒓"
                color: Qt.darker(root.fg, 1.4)
                font.family: root.ff
                font.pixelSize: Style.font.icon
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: strings.t("panel.button.settings")
                color: root.fg
                font.family: root.ff
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.settingsOpen ? "󰅀" : "󰅂"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.ff
              font.pixelSize: Style.font.icon
            }
          }

          // Settings body ---------------------------------------------------
          Column {
            width: parent.width
            visible: root.settingsOpen
            spacing: Style.space(12)

            PanelSectionHeader {
              text: strings.t("panel.section.durations")
              foreground: root.fg
              fontFamily: root.ff
            }

            Grid {
              width: parent.width
              columns: 2
              spacing: Style.space(10)

              NumberField {
                label: strings.t("panel.setting.focus") + " (" + strings.t("panel.minutes") + ")"
                value: root.config.focusMinutes
                from: Model.LIMITS.focusMinutes.min
                to: Model.LIMITS.focusMinutes.max
                fieldWidth: Style.space(96)
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.ff
                onModified: root.setSetting("focusMinutes", value)
              }

              NumberField {
                label: strings.t("panel.setting.break") + " (" + strings.t("panel.minutes") + ")"
                value: root.config.breakMinutes
                from: Model.LIMITS.breakMinutes.min
                to: Model.LIMITS.breakMinutes.max
                fieldWidth: Style.space(96)
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.ff
                onModified: root.setSetting("breakMinutes", value)
              }

              NumberField {
                label: strings.t("panel.setting.longBreak") + " (" + strings.t("panel.minutes") + ")"
                value: root.config.longBreakMinutes
                from: Model.LIMITS.longBreakMinutes.min
                to: Model.LIMITS.longBreakMinutes.max
                fieldWidth: Style.space(96)
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.ff
                onModified: root.setSetting("longBreakMinutes", value)
              }

              NumberField {
                label: strings.t("panel.setting.roundsBeforeLongBreak")
                value: root.config.roundsBeforeLongBreak
                from: Model.LIMITS.roundsBeforeLongBreak.min
                to: Model.LIMITS.roundsBeforeLongBreak.max
                fieldWidth: Style.space(96)
                foreground: root.fg
                accent: Color.accent
                fontFamily: root.ff
                onModified: root.setSetting("roundsBeforeLongBreak", value)
              }
            }

            PanelSeparator { foreground: root.fg }
            PanelSectionHeader {
              text: strings.t("panel.section.behaviour")
              foreground: root.fg
              fontFamily: root.ff
            }

            Toggle {
              width: parent.width
              label: strings.t("panel.setting.autoStartBreaks")
              description: strings.t("panel.setting.autoStartBreaks.description")
              checked: root.config.autoStartBreaks
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.ff
              onClicked: root.toggleSetting("autoStartBreaks")
            }

            Toggle {
              width: parent.width
              label: strings.t("panel.setting.autoStartFocus")
              description: strings.t("panel.setting.autoStartFocus.description")
              checked: root.config.autoStartFocus
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.ff
              onClicked: root.toggleSetting("autoStartFocus")
            }

            Toggle {
              width: parent.width
              label: strings.t("panel.setting.sound")
              description: strings.t("panel.setting.sound.description")
              checked: root.config.sound
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.ff
              onClicked: root.toggleSetting("sound")
            }

            Item {
              width: parent.width
              implicitHeight: volumeLabel.implicitHeight + Style.space(4)

              Text {
                id: volumeLabel
                textFormat: Text.PlainText
                text: strings.t("panel.setting.soundVolume")
                color: root.fg
                font.family: root.ff
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: volumeValue
                textFormat: Text.PlainText
                text: root.config.soundVolume + "%"
                color: Qt.darker(root.fg, 1.4)
                font.family: root.ff
                font.pixelSize: Style.font.bodySmall
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }

              PanelSlider {
                bar: root.bar
                anchors.left: volumeLabel.right
                anchors.leftMargin: Style.space(14)
                anchors.right: volumeValue.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                minimum: Model.LIMITS.soundVolume.min
                maximum: Model.LIMITS.soundVolume.max
                step: 5
                integer: true
                tickCount: 5
                value: root.config.soundVolume
                onReleased: function(v) { root.setSetting("soundVolume", Math.round(v)) }
              }
            }

            Toggle {
              width: parent.width
              label: strings.t("panel.setting.notifications")
              description: strings.t("panel.setting.notifications.description")
              checked: root.config.notifications
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.ff
              onClicked: root.toggleSetting("notifications")
            }

            PanelSeparator { foreground: root.fg }
            PanelSectionHeader {
              text: strings.t("panel.section.appearance")
              foreground: root.fg
              fontFamily: root.ff
            }

            Column {
              width: parent.width
              spacing: Style.space(4)
              Text {
                textFormat: Text.PlainText
                text: strings.t("panel.setting.barFormat")
                color: Qt.darker(root.fg, 1.4)
                font.family: root.ff
                font.pixelSize: Style.font.bodySmall
              }
              Flow {
                width: parent.width
                spacing: Style.spacing.sm
                Repeater {
                  model: [
                    { value: "countdown", key: "panel.format.countdown" },
                    { value: "countdown-label", key: "panel.format.countdown-label" },
                    { value: "percent", key: "panel.format.percent" },
                    { value: "label", key: "panel.format.label" },
                    { value: "icon", key: "panel.format.icon" }
                  ]
                  Button {
                    required property var modelData
                    bordered: true
                    text: strings.t(modelData.key)
                    selected: root.config.barFormat === modelData.value
                    foreground: root.fg
                    fontFamily: root.ff
                    fontSize: Style.font.bodySmall
                    verticalPadding: Style.spacing.sm
                    onClicked: root.setSetting("barFormat", modelData.value)
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(4)
              Text {
                textFormat: Text.PlainText
                text: strings.t("panel.setting.timeFormat")
                color: Qt.darker(root.fg, 1.4)
                font.family: root.ff
                font.pixelSize: Style.font.bodySmall
              }
              Row {
                spacing: Style.spacing.sm
                Repeater {
                  model: [
                    { value: "auto", key: "panel.time.auto" },
                    { value: "always", key: "panel.time.always" },
                    { value: "never", key: "panel.time.never" }
                  ]
                  Button {
                    required property var modelData
                    bordered: true
                    text: strings.t(modelData.key)
                    selected: root.config.timeFormat === modelData.value
                    foreground: root.fg
                    fontFamily: root.ff
                    fontSize: Style.font.bodySmall
                    verticalPadding: Style.spacing.sm
                    onClicked: root.setSetting("timeFormat", modelData.value)
                  }
                }
              }
            }

            Toggle {
              width: parent.width
              label: strings.t("panel.setting.showIcon")
              description: strings.t("panel.setting.showIcon.description")
              checked: root.config.showIcon
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.ff
              onClicked: root.toggleSetting("showIcon")
            }

            Toggle {
              width: parent.width
              label: strings.t("panel.setting.showLabel")
              description: strings.t("panel.setting.showLabel.description")
              checked: root.config.showLabel
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.ff
              onClicked: root.toggleSetting("showLabel")
            }

            LabelledField {
              id: iconFocusField
              labelText: strings.t("panel.setting.iconFocus")
              fieldText: root.config.iconFocus
              onCommitted: function(value) { root.setSetting("iconFocus", value) }
            }

            LabelledField {
              id: iconBreakField
              labelText: strings.t("panel.setting.iconBreak")
              fieldText: root.config.iconBreak
              onCommitted: function(value) { root.setSetting("iconBreak", value) }
            }

            LabelledField {
              id: iconPausedField
              labelText: strings.t("panel.setting.iconPaused")
              fieldText: root.config.iconPaused
              onCommitted: function(value) { root.setSetting("iconPaused", value) }
            }

            LabelledField {
              id: labelField
              labelText: strings.t("panel.setting.label")
              fieldText: root.config.label
              onCommitted: function(value) { root.setSetting("label", value) }
            }

            LabelledField {
              id: breakLabelField
              labelText: strings.t("panel.setting.labelOnBreak")
              fieldText: root.config.labelOnBreak
              onCommitted: function(value) { root.setSetting("labelOnBreak", value) }
            }

            LabelledField {
              id: focusColorField
              labelText: strings.t("panel.setting.focusColor") + " (" + strings.t("panel.setting.colorHint") + ")"
              fieldText: root.config.focusColor
              placeholderText: "#a6adc8"
              onCommitted: function(value) { root.setSetting("focusColor", value) }
            }

            LabelledField {
              id: breakColorField
              labelText: strings.t("panel.setting.breakColor") + " (" + strings.t("panel.setting.colorHint") + ")"
              fieldText: root.config.breakColor
              placeholderText: "#89b4fa"
              onCommitted: function(value) { root.setSetting("breakColor", value) }
            }

            LabelledField {
              id: doneColorField
              labelText: strings.t("panel.setting.doneColor") + " (" + strings.t("panel.setting.colorHint") + ")"
              fieldText: root.config.doneColor
              placeholderText: "#f9e2af"
              onCommitted: function(value) { root.setSetting("doneColor", value) }
            }
          }
        }
      }
    }
  }
}
