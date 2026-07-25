// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

// Keep this bridging header as a thin entry point from Swift into the Objective-C++ layer.
// The actual libtorrent integration lives in App/LibtorrentShim.
#import "../App/LibtorrentShim/LibtorrentSessionBridge.h"
