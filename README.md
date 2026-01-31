# Lektr KOReader Sync Plugin

This plugin allows you to sync highlights from your KOReader device directly to your self-hosted Lektr instance.

## Features

- "Sync Current Book" menu item, auto-sync on open/close.
- Uploads highlights, notes, and progress to Lektr.
- Supports Email/Password Login (Recommended).
- Supports manual Auth Token (Advanced).

## Installation

1. Connect your KOReader device to your computer via USB.
2. Navigate to `koreader/plugins/`.
3. Copy the `lektr.koplugin` folder from this directory into `koreader/plugins/`.
4. Eject/Disconnect your device and restart KOReader.

## Configuration

1. Open a book in KOReader.
2. Go to **Search/Tools** > **Lektr Sync** > **Settings**.
3. Tap **Set API URL** and enter your server URL (e.g., `http://192.168.1.100:3000/api/v1/import`).
4. Tap **Login** and enter your Lektr email and password.
   - **Auto-Sync on Open/Close**: Check this to automatically sync highlights when you open or close a book.
   - Alternatively, you can use **Set Auth Token (Manual)** if login fails.

## Usage

1. Open **Lektr Sync** menu.
2. Tap **Sync Current Book** for the active document.
3. Tap **Sync All History** to scan and upload highlights from all your previously read books.
