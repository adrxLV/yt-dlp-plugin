pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.adriano.media-downloader"
  ipcTarget: "io.github.adriano.media-downloader"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // State properties
  // "idle" | "searching" | "results" | "configure" | "downloading" | "complete" | "error"
  property string viewState: "idle"
  property string statusText: "Search YouTube or paste any media link"
  property string queryText: ""
  property var searchResults: []
  property var selectedItem: null
  property var historyList: []
  property string activeMode: "video" // "video" | "audio"
  property string selectedQuality: "best" // "best" | "1080" | "720" | "480"
  property string selectedAudioFormat: "mp3" // "mp3" | "m4a" | "flac" | "opus"
  property string customOutDir: ""
  property string errorMessage: ""

  // Live download progress state
  property real downloadPercent: 0
  property string downloadSpeed: ""
  property string downloadEta: ""
  property string downloadDownloaded: ""
  property string downloadTotal: ""
  property string downloadStatusPhrase: "Starting download…"
  property var completedItem: null

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentDim: Qt.darker(contentForeground, 1.5)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string helperPath: {
    var url = decodeURIComponent(String(Qt.resolvedUrl("downloaderctl.py")))
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }

  readonly property string defaultVideoDir: setting("defaultVideoDir", "~/Downloads")
  readonly property string defaultAudioDir: setting("defaultAudioDir", "~/Music")
  readonly property string targetDir: customOutDir !== ""
    ? customOutDir
    : (activeMode === "audio" ? defaultAudioDir : defaultVideoDir)

  function open() {
    root.controller.show()
    loadHistory()
    Qt.callLater(function() {
      if (root.opened && searchField) {
        searchField.forceActiveFocus()
      }
    })
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    loadHistory()
  }

  function loadHistory() {
    if (!historyProcess.running) {
      historyProcess.command = [root.helperPath, "history"]
      historyProcess.running = true
    }
  }

  function clearHistory() {
    if (!clearHistoryProcess.running) {
      clearHistoryProcess.command = [root.helperPath, "clear-history"]
      clearHistoryProcess.running = true
    }
  }

  function handleSearchSubmit() {
    var raw = searchField.text.trim()
    if (!raw) return
    root.queryText = raw

    if (Model.isUrl(raw)) {
      root.statusText = "Fetching media metadata…"
      root.viewState = "searching"
      infoProcess.command = [root.helperPath, "info", raw]
      infoProcess.running = true
    } else {
      root.statusText = "Searching YouTube for \"" + raw + "\"…"
      root.viewState = "searching"
      searchProcess.command = [root.helperPath, "search", raw, "--limit", "5"]
      searchProcess.running = true
    }
  }

  function selectMedia(item) {
    root.selectedItem = item
    root.viewState = "configure"
    root.statusText = "Configure download format & quality"
  }

  function startDownload() {
    if (!root.selectedItem || downloadProcess.running) return
    root.downloadPercent = 0
    root.downloadSpeed = "—"
    root.downloadEta = "—"
    root.downloadDownloaded = "0 MB"
    root.downloadTotal = "—"
    root.downloadStatusPhrase = "Preparing download…"
    root.completedItem = null
    root.errorMessage = ""
    root.viewState = "downloading"
    root.statusText = "Downloading " + root.selectedItem.title

    var cmd = [
      root.helperPath, "download",
      "--url", root.selectedItem.url,
      "--mode", root.activeMode,
      "--quality", root.selectedQuality,
      "--audio-format", root.selectedAudioFormat,
      "--out-dir", root.targetDir
    ]
    downloadProcess.command = cmd
    downloadProcess.running = true
  }

  function cancelDownload() {
    if (downloadProcess.running) {
      downloadProcess.running = false
      root.statusText = "Download cancelled"
      root.viewState = root.selectedItem ? "configure" : "idle"
    }
  }

  function openPath(path) {
    if (!path) return
    Quickshell.execDetached(["xdg-open", path])
  }

  function showInFolder(path) {
    if (!path) return
    var dir = path.substring(0, path.lastIndexOf("/"))
    if (!dir) dir = root.targetDir.replace("~", Quickshell.env("HOME") || "")
    Quickshell.execDetached(["xdg-open", dir])
  }

  function resetToIdle() {
    root.viewState = "idle"
    root.selectedItem = null
    root.errorMessage = ""
    root.statusText = "Search YouTube or paste any media link"
    loadHistory()
  }

  function handleDownloadStream(line) {
    if (!line) return
    var prog = Model.parseProgressLine(line)
    if (prog) {
      var pct = parseFloat(String(prog.percent || "").replace("%", ""))
      if (!isNaN(pct)) root.downloadPercent = Math.max(0, Math.min(100, pct))
      if (prog.speed) root.downloadSpeed = prog.speed
      if (prog.eta) root.downloadEta = prog.eta
      if (prog.downloaded) root.downloadDownloaded = prog.downloaded
      if (prog.total) root.downloadTotal = prog.total
      if (prog.status) root.downloadStatusPhrase = prog.status === "downloading" ? "Downloading streams…" : prog.status
      return
    }

    var comp = Model.parseCompleteLine(line)
    if (comp) {
      root.completedItem = comp
      root.viewState = "complete"
      root.statusText = "Download completed!"
      loadHistory()
      return
    }

    var err = Model.parseErrorLine(line)
    if (err) {
      root.errorMessage = err.message || "Download failed"
      root.viewState = "error"
      root.statusText = "Error during download"
    }
  }

  onOpenedChanged: {
    if (opened) {
      loadHistory()
      Qt.callLater(function() {
        if (searchField) searchField.forceActiveFocus()
      })
    }
  }

  // Processes
  Process {
    id: searchProcess
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var res = Model.parseJsonSafe(text, null)
        if (res && res.status === "ok" && res.results) {
          root.searchResults = res.results
          root.viewState = res.results.length > 0 ? "results" : "idle"
          root.statusText = res.results.length > 0
            ? "Found " + res.results.length + " results for \"" + root.queryText + "\""
            : "No results found for \"" + root.queryText + "\""
        } else {
          root.errorMessage = (res && res.message) ? res.message : "Search query failed"
          root.viewState = "error"
          root.statusText = "Search error"
        }
      }
    }
  }

  Process {
    id: infoProcess
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var res = Model.parseJsonSafe(text, null)
        if (res && res.status === "ok" && res.result) {
          root.selectMedia(res.result)
        } else {
          root.errorMessage = (res && res.message) ? res.message : "Could not fetch metadata for URL"
          root.viewState = "error"
          root.statusText = "URL extraction error"
        }
      }
    }
  }

  Process {
    id: downloadProcess
    command: ["true"]
    stdout: SplitParser {
      onRead: function(line) { root.handleDownloadStream(line) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim() && root.viewState === "downloading") {
          // Log or check critical errors
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.viewState === "downloading") {
        root.viewState = "error"
        root.statusText = "Download process exited with code " + exitCode
      }
    }
  }

  Process {
    id: historyProcess
    command: ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var res = Model.parseJsonSafe(text, null)
        if (res && res.status === "ok" && res.history) {
          root.historyList = res.history
        }
      }
    }
  }

  Process {
    id: clearHistoryProcess
    command: ["true"]
    onExited: function(code) {
      if (code === 0) {
        root.historyList = []
        root.statusText = "History cleared"
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: searchField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: mainColumn
        width: parent.width
        spacing: Style.space(12)

        // Header
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            textFormat: Text.PlainText
            text: root.hostWidget && root.hostWidget.barIcon
              ? root.hostWidget.barIcon
              : Model.defaultIcon()
            color: Color.accent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.heading
            Layout.alignment: Qt.AlignVCenter
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(1)

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: "Media Downloader"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              text: root.statusText
              color: root.contentDim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          PanelActionButton {
            iconText: "󰝰"
            tooltipText: "Open Downloads folder"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.openPath(root.defaultVideoDir)
          }

          PanelActionButton {
            iconText: "󰝚"
            tooltipText: "Open Music folder"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.openPath(root.defaultAudioDir)
          }

          PanelActionButton {
            iconText: "󰑐"
            tooltipText: "Refresh / Reset"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.resetToIdle()
          }
        }

        // Search Bar Row
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Paste YouTube/media link or search query…"
            maximumLength: 300
            foreground: root.contentForeground
            font.family: root.contentFontFamily
            enabled: root.viewState !== "downloading"
            onAccepted: root.handleSearchSubmit()
            Keys.onEscapePressed: root.close()
          }

          Button {
            id: searchBtn
            text: Model.isUrl(searchField.text) ? "Fetch" : "Search"
            iconText: Model.isUrl(searchField.text) ? "󰌷" : "󰍉"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            bordered: true
            active: searchField.text.trim().length > 0
            enabled: searchField.text.trim().length > 0 && root.viewState !== "downloading"
            onClicked: root.handleSearchSubmit()
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.contentForeground
        }

        // ==========================================
        // STATE: SEARCHING
        // ==========================================
        ColumnLayout {
          visible: root.viewState === "searching"
          width: parent.width
          spacing: Style.space(12)

          Item { height: Style.space(10); width: 1 }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰑐"
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.heading * 1.8
            color: Color.accent

            RotationAnimation on rotation {
              running: root.viewState === "searching"
              loops: Animation.Infinite
              from: 0
              to: 360
              duration: 1100
            }
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.statusText
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Item { height: Style.space(10); width: 1 }
        }

        // ==========================================
        // STATE: RESULTS
        // ==========================================
        Column {
          visible: root.viewState === "results"
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            Text {
              Layout.fillWidth: true
              text: "SEARCH RESULTS"
              color: root.contentDim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }

            Text {
              text: root.searchResults.length + " items"
              color: root.contentDim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.searchResults

            Rectangle {
              id: resultCard
              required property var modelData
              required property int index

              width: parent.width
              implicitHeight: Style.space(64)
              radius: Style.cornerRadius
              color: itemHover.hovered ? Util.alpha(Color.accent, 0.14) : Util.alpha(root.contentForeground, 0.04)
              border.width: 1
              border.color: itemHover.hovered ? Util.alpha(Color.accent, 0.45) : Util.alpha(root.contentForeground, 0.10)

              Behavior on color { ColorAnimation { duration: 120 } }
              Behavior on border.color { ColorAnimation { duration: 120 } }

              HoverHandler { id: itemHover }
              TapHandler { onTapped: root.selectMedia(resultCard.modelData) }

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(10)

                // Thumbnail Container
                Rectangle {
                  Layout.preferredWidth: Style.space(84)
                  Layout.preferredHeight: Style.space(50)
                  radius: Math.max(2, Style.cornerRadius - 2)
                  color: Qt.darker(root.contentForeground, 3.0)
                  clip: true

                  Image {
                    anchors.fill: parent
                    source: resultCard.modelData.thumbnail || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                  }

                  // Duration badge
                  Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Style.space(3)
                    radius: 2
                    color: Qt.rgba(0, 0, 0, 0.78)
                    implicitWidth: durText.implicitWidth + Style.space(6)
                    implicitHeight: durText.implicitHeight + Style.space(2)

                    Text {
                      id: durText
                      anchors.centerIn: parent
                      text: resultCard.modelData.duration_str || "--:--"
                      color: "#ffffff"
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption - 1
                      font.bold: true
                    }
                  }
                }

                // Info column
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    Layout.fillWidth: true
                    text: resultCard.modelData.title || "Untitled"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                  }

                  Text {
                    Layout.fillWidth: true
                    text: resultCard.modelData.channel || ""
                    color: root.contentDim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                // Select Icon
                Text {
                  text: "󰄾"
                  color: itemHover.hovered ? Color.accent : root.contentDim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.title
                  Layout.alignment: Qt.AlignVCenter
                  Layout.rightMargin: Style.space(6)
                }
              }
            }
          }
        }

        // ==========================================
        // STATE: CONFIGURE DOWNLOAD
        // ==========================================
        Column {
          visible: root.viewState === "configure" && root.selectedItem !== null
          width: parent.width
          spacing: Style.space(12)

          // Selected Hero Card
          Rectangle {
            width: parent.width
            implicitHeight: Style.space(76)
            radius: Style.cornerRadius
            color: Util.alpha(Color.accent, 0.08)
            border.width: 1
            border.color: Util.alpha(Color.accent, 0.25)

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(10)

              Rectangle {
                Layout.preferredWidth: Style.space(96)
                Layout.preferredHeight: Style.space(58)
                radius: Math.max(2, Style.cornerRadius - 2)
                color: Qt.darker(root.contentForeground, 3.0)
                clip: true

                Image {
                  anchors.fill: parent
                  source: root.selectedItem ? (root.selectedItem.thumbnail || "") : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }

                Rectangle {
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.margins: Style.space(3)
                  radius: 2
                  color: Qt.rgba(0, 0, 0, 0.78)
                  implicitWidth: selDurText.implicitWidth + Style.space(6)
                  implicitHeight: selDurText.implicitHeight + Style.space(2)

                  Text {
                    id: selDurText
                    anchors.centerIn: parent
                    text: root.selectedItem ? (root.selectedItem.duration_str || "--:--") : ""
                    color: "#ffffff"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption - 1
                    font.bold: true
                  }
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                  Layout.fillWidth: true
                  text: root.selectedItem ? root.selectedItem.title : ""
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  wrapMode: Text.Wrap
                }

                Text {
                  Layout.fillWidth: true
                  text: root.selectedItem ? root.selectedItem.channel : ""
                  color: root.contentDim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }

          // Format Mode Selector (Video vs Audio)
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "DOWNLOAD FORMAT"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                Layout.fillWidth: true
                iconText: "󰕑"
                text: "Video (MP4)"
                bordered: true
                active: root.activeMode === "video"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.activeMode = "video"
              }

              Button {
                Layout.fillWidth: true
                iconText: "󰝚"
                text: "Audio (Music)"
                bordered: true
                active: root.activeMode === "audio"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.activeMode = "audio"
              }
            }
          }

          // Video Quality Selector
          Column {
            visible: root.activeMode === "video"
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "VIDEO QUALITY"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Button {
                Layout.fillWidth: true
                text: "Best"
                bordered: true
                active: root.selectedQuality === "best"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                onClicked: root.selectedQuality = "best"
              }

              Button {
                Layout.fillWidth: true
                text: "1080p"
                bordered: true
                active: root.selectedQuality === "1080"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                onClicked: root.selectedQuality = "1080"
              }

              Button {
                Layout.fillWidth: true
                text: "720p"
                bordered: true
                active: root.selectedQuality === "720"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                onClicked: root.selectedQuality = "720"
              }

              Button {
                Layout.fillWidth: true
                text: "480p"
                bordered: true
                active: root.selectedQuality === "480"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                onClicked: root.selectedQuality = "480"
              }
            }
          }

          // Audio Format Selector
          Column {
            visible: root.activeMode === "audio"
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "AUDIO CODEC"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Button {
                Layout.fillWidth: true
                text: "MP3"
                bordered: true
                active: root.selectedAudioFormat === "mp3"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                onClicked: root.selectedAudioFormat = "mp3"
              }

              Button {
                Layout.fillWidth: true
                text: "M4A / AAC"
                bordered: true
                active: root.selectedAudioFormat === "m4a"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                onClicked: root.selectedAudioFormat = "m4a"
              }

              Button {
                Layout.fillWidth: true
                text: "FLAC"
                bordered: true
                active: root.selectedAudioFormat === "flac"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                onClicked: root.selectedAudioFormat = "flac"
              }

              Button {
                Layout.fillWidth: true
                text: "Opus"
                bordered: true
                active: root.selectedAudioFormat === "opus"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                onClicked: root.selectedAudioFormat = "opus"
              }
            }
          }

          // Destination Directory
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Save to:"
              color: root.contentDim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              Layout.fillWidth: true
              text: root.targetDir
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }
          }

          // Action Buttons
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              iconText: "󰁌"
              text: "Back"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: root.viewState = (root.searchResults.length > 0 ? "results" : "idle")
            }

            Button {
              Layout.fillWidth: true
              iconText: "󰐕"
              text: "Start Download"
              foreground: Color.accent
              fontFamily: root.contentFontFamily
              bordered: true
              active: true
              onClicked: root.startDownload()
            }
          }
        }

        // ==========================================
        // STATE: DOWNLOADING
        // ==========================================
        Column {
          visible: root.viewState === "downloading"
          width: parent.width
          spacing: Style.space(12)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: root.selectedItem ? root.selectedItem.title : "Downloading Media"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              text: Math.round(root.downloadPercent) + "%"
              color: Color.accent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          // Progress Bar
          Item {
            width: parent.width
            implicitHeight: Style.space(10)

            Rectangle {
              id: progTrack
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
            }

            Rectangle {
              id: progFill
              anchors.left: progTrack.left
              anchors.verticalCenter: progTrack.verticalCenter
              height: progTrack.height
              radius: progTrack.radius
              color: Color.accent
              width: Math.max(progTrack.height, progTrack.width * (root.downloadPercent / 100))

              Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

              SequentialAnimation on opacity {
                running: root.viewState === "downloading"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.65; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.65; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
              }
            }
          }

          // Stats Grid
          RowLayout {
            width: parent.width

            Column {
              Layout.fillWidth: true
              Text { text: "Speed"; color: root.contentDim; font.pixelSize: Style.font.caption; font.family: root.contentFontFamily }
              Text { text: root.downloadSpeed || "—"; color: root.contentForeground; font.pixelSize: Style.font.bodySmall; font.bold: true; font.family: root.contentFontFamily }
            }

            Column {
              Layout.fillWidth: true
              Text { text: "ETA"; color: root.contentDim; font.pixelSize: Style.font.caption; font.family: root.contentFontFamily }
              Text { text: root.downloadEta || "—"; color: root.contentForeground; font.pixelSize: Style.font.bodySmall; font.bold: true; font.family: root.contentFontFamily }
            }

            Column {
              Layout.fillWidth: true
              Text { text: "Progress"; color: root.contentDim; font.pixelSize: Style.font.caption; font.family: root.contentFontFamily }
              Text { text: (root.downloadDownloaded || "0 MB") + " / " + (root.downloadTotal || "—"); color: root.contentForeground; font.pixelSize: Style.font.bodySmall; font.bold: true; font.family: root.contentFontFamily }
            }
          }

          Button {
            width: parent.width
            iconText: "󰅖"
            text: "Cancel Download"
            foreground: Color.urgent
            fontFamily: root.contentFontFamily
            bordered: true
            onClicked: root.cancelDownload()
          }
        }

        // ==========================================
        // STATE: COMPLETE
        // ==========================================
        Column {
          visible: root.viewState === "complete"
          width: parent.width
          spacing: Style.space(12)

          Rectangle {
            width: parent.width
            implicitHeight: Style.space(80)
            radius: Style.cornerRadius
            color: Util.alpha(Color.accent, 0.12)
            border.width: 1
            border.color: Util.alpha(Color.accent, 0.4)

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(12)

              Text {
                text: "󰄬"
                color: Color.accent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.heading * 1.5
                Layout.alignment: Qt.AlignVCenter
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                  text: "Download Completed!"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  Layout.fillWidth: true
                  text: root.completedItem ? root.completedItem.filename : ""
                  color: root.contentDim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  text: root.completedItem ? ("Size: " + (root.completedItem.size || "Unknown")) : ""
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              Layout.fillWidth: true
              iconText: "󰝰"
              text: "Open File"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: root.openPath(root.completedItem ? root.completedItem.path : "")
            }

            Button {
              Layout.fillWidth: true
              iconText: "󰝰"
              text: "Show Folder"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              bordered: true
              onClicked: root.showInFolder(root.completedItem ? root.completedItem.path : "")
            }

            Button {
              Layout.fillWidth: true
              iconText: "󰑐"
              text: "Done"
              foreground: Color.accent
              fontFamily: root.contentFontFamily
              bordered: true
              active: true
              onClicked: root.resetToIdle()
            }
          }
        }

        // ==========================================
        // STATE: ERROR
        // ==========================================
        Column {
          visible: root.viewState === "error"
          width: parent.width
          spacing: Style.space(10)

          Rectangle {
            width: parent.width
            implicitHeight: Style.space(60)
            radius: Style.cornerRadius
            color: Util.alpha(Color.urgent, 0.12)
            border.width: 1
            border.color: Util.alpha(Color.urgent, 0.35)

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(10)

              Text {
                text: "󰅖"
                color: Color.urgent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.heading
              }

              Text {
                Layout.fillWidth: true
                text: root.errorMessage || "An unexpected error occurred."
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
              }
            }
          }

          Button {
            width: parent.width
            iconText: "󰁌"
            text: "Back to Search"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            bordered: true
            onClicked: root.resetToIdle()
          }
        }

        // ==========================================
        // STATE: IDLE (HISTORY & RECENTS)
        // ==========================================
        Column {
          visible: root.viewState === "idle"
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width

            Text {
              Layout.fillWidth: true
              text: "RECENT DOWNLOADS"
              color: root.contentDim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: 1
            }

            PanelActionButton {
              visible: root.historyList.length > 0
              iconText: "󰩹"
              tooltipText: "Clear download history"
              foreground: Color.urgent
              hoverColor: Color.urgent
              fontFamily: root.contentFontFamily
              onClicked: root.clearHistory()
            }
          }

          Text {
            visible: root.historyList.length === 0
            text: "No recent downloads yet. Search above or paste a video URL!"
            color: root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
          }

          Repeater {
            model: root.historyList.slice(0, 5)

            Rectangle {
              id: histCard
              required property var modelData
              required property int index

              width: parent.width
              implicitHeight: Style.space(48)
              radius: Style.cornerRadius
              color: histHover.hovered ? Util.alpha(Color.accent, 0.12) : Util.alpha(root.contentForeground, 0.03)
              border.width: 1
              border.color: histHover.hovered ? Util.alpha(Color.accent, 0.35) : Util.alpha(root.contentForeground, 0.08)

              Behavior on color { ColorAnimation { duration: 120 } }

              HoverHandler { id: histHover }

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(8)

                Text {
                  text: histCard.modelData.mode === "audio" ? "󰝚" : "󰕑"
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  Layout.leftMargin: Style.space(4)
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Text {
                    Layout.fillWidth: true
                    text: histCard.modelData.title || histCard.modelData.filename || "Untitled"
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: (histCard.modelData.time_str || "") + (histCard.modelData.size ? (" · " + histCard.modelData.size) : "")
                    color: root.contentDim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption - 1
                  }
                }

                PanelActionButton {
                  iconText: "󰝰"
                  tooltipText: "Open file"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.openPath(histCard.modelData.path)
                }

                PanelActionButton {
                  iconText: "󰝰"
                  tooltipText: "Open folder"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.showInFolder(histCard.modelData.path)
                }
              }
            }
          }
        }
      }
    }
  }
}
