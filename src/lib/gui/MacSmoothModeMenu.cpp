/*
 * Deskflow -- mouse and keyboard sharing utility
 * SPDX-FileCopyrightText: (C) 2026 lxf82dev <lxf82dev@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception
 */

#include "MacSmoothModeMenu.h"

#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMap>
#include <QSaveFile>
#include <QTimer>
#include <QUrl>

#include <utility>

MacSmoothModeMenu::MacSmoothModeMenu(QWidget *parent, QString controlPath, QString statusPath)
    : QMenu(tr("Smooth Mode"), parent),
      m_controlPath(
          controlPath.isEmpty() ? QDir::homePath() + "/Library/Application Support/DeskflowMXAWDL/control"
                                : std::move(controlPath)
      ),
      m_statusPath(statusPath.isEmpty() ? "/Library/Logs/DeskflowMXAWDL/status" : std::move(statusPath))
{
  m_summary = addAction(QString());
  m_summary->setObjectName("smoothStatus");
  m_summary->setEnabled(false);
  addSeparator();
  m_automatic = addAction(tr("Automatic smoothing"));
  m_automatic->setObjectName("smoothAutomatic");
  m_automatic->setCheckable(true);
  m_airdrop = addAction(tr("Allow AirDrop for 10 minutes"));
  m_airdrop->setObjectName("smoothAirDrop");
  m_airdrop->setCheckable(true);
  m_resume = addAction(tr("Resume automatic mode now"));
  m_resume->setObjectName("smoothResume");
  addSeparator();
  auto *log = addAction(tr("Show controller log"));
  connect(log, &QAction::triggered, this, [] {
    QDesktopServices::openUrl(QUrl::fromLocalFile("/Library/Logs/DeskflowMXAWDL/guard.log"));
  });
  auto *help = addAction(tr("Setup and help"));
  connect(help, &QAction::triggered, this, [] {
    QDesktopServices::openUrl(
        QUrl("https://github.com/lxf82dev/deskflow/blob/macos-logitech-fixes/tools/macos-smooth-mode/README.md")
    );
  });
  connect(m_automatic, &QAction::triggered, this, [this](bool checked) {
    writeControl(checked ? "auto\n" : "disabled\n");
  });
  connect(m_airdrop, &QAction::triggered, this, [this] {
    writeControl("pause_until=" + QByteArray::number(QDateTime::currentSecsSinceEpoch() + 600) + '\n');
  });
  connect(m_resume, &QAction::triggered, this, [this] { writeControl("auto\n"); });
  connect(this, &QMenu::aboutToShow, this, &MacSmoothModeMenu::refresh);
  auto *timer = new QTimer(this);
  connect(timer, &QTimer::timeout, this, &MacSmoothModeMenu::refresh);
  timer->start(1000);
  refresh();
}

void MacSmoothModeMenu::refresh()
{
  const QFileInfo statusInfo(m_statusPath);
  const auto age = statusInfo.lastModified().secsTo(QDateTime::currentDateTime());
  QFile status(m_statusPath);
  QMap<QByteArray, QByteArray> fields;
  if (statusInfo.isFile() && !statusInfo.isSymLink() && statusInfo.size() <= 4096 && age >= -5 && age <= 15 &&
      status.open(QIODevice::ReadOnly)) {
    for (const auto &line : status.read(4096).split('\n')) {
      const auto separator = line.indexOf('=');
      if (separator > 0)
        fields.insert(line.left(separator), line.mid(separator + 1));
    }
  }
  QFile control(m_controlPath);
  const QFileInfo controlInfo(control);
  const bool available = fields.value("version") == "1" && controlInfo.isFile() && !controlInfo.isSymLink() &&
                         controlInfo.size() <= 128 && control.open(QIODevice::ReadOnly);
  const auto preference = available ? control.read(128).trimmed() : QByteArray();
  const bool paused =
      preference.startsWith("pause_until=") && preference.mid(12).toLongLong() > QDateTime::currentSecsSinceEpoch();
  const auto mode = fields.value("mode");
  QString summary = tr("Controller offline — run setup");
  if (available) {
    if (mode == "smooth")
      summary = tr("Client active — AWDL suppressed");
    else if (mode == "allowed")
      summary = tr("Server active — AirDrop allowed");
    else if (mode == "waiting")
      summary = tr("Waiting for a Deskflow switch");
    else if (mode == "deskflow-stopped")
      summary = tr("Deskflow stopped — AirDrop allowed");
    else if (mode == "airdrop")
      summary = tr("AirDrop override active");
    else if (mode == "disabled")
      summary = tr("Automatic smoothing is off");
    else if (mode == "stopped")
      summary = tr("Controller stopped");
    else
      summary = tr("Controller error — see log");
  }
  m_summary->setText(summary);
  m_automatic->setEnabled(available);
  m_automatic->setChecked(available && preference != "disabled");
  m_airdrop->setEnabled(available && !paused);
  m_airdrop->setChecked(paused);
  m_resume->setEnabled(available && (paused || preference == "disabled"));
}

void MacSmoothModeMenu::writeControl(const QByteArray &value)
{
  // Do not silently create a control file when setup is absent or replace a link.
  const QFileInfo info(m_controlPath);
  if (!info.isFile() || info.isSymLink()) {
    Q_EMIT controlError(tr("The Smooth Mode control file is missing or invalid. Run setup first."));
    refresh();
    return;
  }
  QSaveFile file(m_controlPath);
  if (!file.open(QIODevice::WriteOnly) || !file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner) ||
      file.write(value) != value.size() || !file.commit()) {
    Q_EMIT controlError(tr("Could not update Smooth Mode: %1").arg(file.errorString()));
  }
  refresh();
}
