import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// EasyTimer: one timer, one editable duration. The bar label and this popup
// are fully configurable (format, glyph, label, colors, sound, notifications),
// but there are no modes, phases or rounds.
//
// Runtime state is shared in ~/.local/state/omarchy/easytimer.json so every
// monitor shows the same clock. The primary-screen instance ("leader") alone
// owns the notification and chime.
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

  function setMinutes(value) {
    setSetting("minutes", Model.clampSetting("minutes", value))
  }

  function adjustMinutes(delta) { setMinutes(config.minutes + delta) }

  // ---- Runtime state ------------------------------------------------------
  property var state: Model.initialState(config)
  property real now: Date.now()
  property bool settingsOpen: false
  property real wheelAccumulator: 0
  property bool stateLoaded: false

  readonly property int remaining: Model.remainingMs(state, config, now)
  readonly property real progress: Model.progress(state, config, now)
  readonly property bool running: state.status === "running"
  readonly property bool paused: state.status === "paused"
  readonly property bool done: state.status === "done"
  readonly property string statusTitle: strings.t("panel.status." + state.status)
  readonly property string barLabel: Model.barText(state, config, now)

  readonly property var hostWindow: QsWindow.window
  readonly property bool isLeader: {
    var screens = Quickshell.screens
    if (!hostWindow || !hostWindow.screen || screens.length === 0) return true
    return hostWindow.screen.name === screens[0].name
  }

  readonly property color buttonForeground: config.color !== "" ? config.color : fg
  readonly property color buttonUrgent: config.doneColor !== "" ? config.doneColor : urgent

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.state = Model.parseState(text(), root.config)
      root.stateLoaded = true
    }
    onLoadFailed: {
      root.state = Model.initialState(root.config)
      root.stateLoaded = true
    }
  }

  // A length change from the panel, `omarchy bar set`, or anywhere else
  // resets the timer to the new duration. Color/glyph edits leave it alone.
  onConfigChanged: {
    if (!stateLoaded) return
    if (Math.round(state.durationMs / 60000) !== config.minutes)
      commit(Model.initialState({ minutes: config.minutes }))
  }

  function commit(next) {
    root.now = Date.now()
    next.updatedAt = root.now
    root.state = next
    stateFile.setText(Model.serializeState(next, root.now))
  }

  function startTimer() { commit(Model.start(state, config, Date.now())) }
  function pauseTimer() { commit(Model.pause(state, Date.now())) }
  function toggleTimer() { commit(Model.togglePause(state, config, Date.now())) }
  function resetTimer() { commit(Model.reset(state, config)) }

  function finishPhase() {
    commit(Model.finish(state, config))
    if (!isLeader) return

    if (config.notifications)
      Util.execArgv(["omarchy-notification-send", "-g", config.glyph,
        strings.t("notify.done.title"),
        strings.t("notify.done.body").arg(config.minutes)])
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
    function minutes(value: int): void { root.setMinutes(value) }
    function settingsToggle(): void { root.open(); root.settingsOpen = true }
    function status(): string {
      return JSON.stringify({ state: root.state, settings: root.config })
    }
  }

  // Reusable labeled input for the appearance section. Fields report focus
  // through a map so the key catcher never forwards references to items that
  // are created later inside the panel.
  component LabelledField: Column {
    id: field
    property string labelText: ""
    property string fieldText: ""
    property string placeholderText: ""
    property string fieldKey: ""
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
      onActiveFocusChanged: {
        if (activeFocus) selectAll()
        root.setFieldEditing(field.fieldKey, activeFocus)
      }
    }
  }

  property var editingFields: ({})
  property bool editing: false

  function setFieldEditing(key, value) {
    var map = {}
    for (var k in root.editingFields) map[k] = root.editingFields[k]
    map[key] = value
    root.editingFields = map
    var any = false
    for (var m in map) if (map[m]) { any = true; break }
    root.editing = any
  }

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
    active: root.done
    dimmed: root.paused
    horizontalMargin: config.showIcon && config.barFormat !== "icon" ? 8.5 : 6.5
    centerFigures: config.barFormat !== "icon"
    tooltipText: root.done
      ? strings.t("panel.status.done")
      : root.statusTitle + " · " + strings.t("panel.left").arg(Model.formatTime(root.remaining, config.timeFormat))

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleTimer()
      else if (b === Qt.MiddleButton) root.resetTimer()
      else root.toggle()
    }

    onWheelMoved: function(delta) {
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0) root.adjustMinutes(wheel.steps)
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
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(1000))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onActivateRequested: root.toggleTimer()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "p") root.toggleTimer()
        else if (t === "r") root.resetTimer()
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
            meta: root.statusTitle
            detail: root.config.minutes + " " + strings.t("panel.minutes")
            foreground: root.fg
            fontFamily: root.ff
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: Model.glyph(root.state, root.config)
                color: root.done ? root.buttonUrgent : root.buttonForeground
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
              color: root.done ? root.buttonUrgent : root.fg
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
                width: root.done ? parent.width : parent.width * root.progress
                radius: parent.radius
                color: root.done ? root.buttonUrgent : Color.accent
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.Linear } }
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.done ? strings.t("panel.status.done")
                : root.running
                  ? strings.t("panel.endsAt").arg(Qt.formatTime(new Date(root.state.endAt), "HH:mm"))
                  : strings.t("panel.left").arg(Model.formatTime(root.remaining, root.config.timeFormat))
              color: Qt.darker(root.fg, 1.4)
              font.family: root.ff
              font.pixelSize: Style.font.caption
            }
          }

          // Controls --------------------------------------------------------
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spacing.sm

            Button {
              bordered: true
              iconText: "󰍴"
              text: "-1"
              tooltipText: strings.t("panel.setting.minutes")
              foreground: root.fg
              fontFamily: root.ff
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.sm
              onClicked: root.adjustMinutes(-1)
            }

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
              iconText: "󰐕"
              text: "+1"
              tooltipText: strings.t("panel.setting.minutes")
              foreground: root.fg
              fontFamily: root.ff
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.sm
              onClicked: root.adjustMinutes(1)
            }

            Button {
              bordered: true
              iconText: "󰜉"
              text: strings.t("panel.button.reset")
              foreground: root.fg
              fontFamily: root.ff
              onClicked: root.resetTimer()
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
              text: strings.t("panel.section.timer")
              foreground: root.fg
              fontFamily: root.ff
            }

            NumberField {
              label: strings.t("panel.setting.minutes") + " (" + strings.t("panel.minutes") + ")"
              value: root.config.minutes
              from: Model.LIMITS.minutes.min
              to: Model.LIMITS.minutes.max
              fieldWidth: Style.space(110)
              foreground: root.fg
              accent: Color.accent
              fontFamily: root.ff
              onModified: function(v) { root.setMinutes(v) }
            }

            PanelSeparator { foreground: root.fg }
            PanelSectionHeader {
              text: strings.t("panel.section.behaviour")
              foreground: root.fg
              fontFamily: root.ff
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
              fieldKey: "glyph"
              labelText: strings.t("panel.setting.glyph")
              fieldText: root.config.glyph
              onCommitted: function(value) { root.setSetting("glyph", value) }
            }

            LabelledField {
              fieldKey: "glyphPaused"
              labelText: strings.t("panel.setting.glyphPaused")
              fieldText: root.config.glyphPaused
              onCommitted: function(value) { root.setSetting("glyphPaused", value) }
            }

            LabelledField {
              fieldKey: "label"
              labelText: strings.t("panel.setting.label")
              fieldText: root.config.label
              onCommitted: function(value) { root.setSetting("label", value) }
            }

            LabelledField {
              fieldKey: "color"
              labelText: strings.t("panel.setting.color") + " (" + strings.t("panel.setting.colorHint") + ")"
              fieldText: root.config.color
              placeholderText: "#a6adc8"
              onCommitted: function(value) { root.setSetting("color", value) }
            }

            LabelledField {
              fieldKey: "doneColor"
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
