# Lektr KOReader Sync Plugin

[![GitHub stars](https://img.shields.io/github/stars/lektr/lektr-koreader-plugin?style=social)](https://github.com/lektr/lektr-koreader-plugin)

This plugin allows you to sync highlights from your KOReader device directly to your self-hosted Lektr instance.

It is designed to work seamlessly with [Lektr App](https://www.lektr.app), a self-hosted eBook reader and highlight manager.

## Features

- "Sync Current Book" menu item, auto-sync on open/close.
- Uploads highlights, notes, and progress to Lektr.
- Supports Email/Password Login (Recommended).
- Supports manual Auth Token (Advanced).

## Installation

### General

The goal is to place the `lektr.koplugin` folder into KOReader's plugins directory.

### Kindle

1. Connect your Kindle to your computer via USB.
2. Open the Kindle drive and navigate to `koreader/plugins/`.
3. Copy the `lektr.koplugin` folder from this repository into `koreader/plugins/`.
4. Eject/Disconnect your device and restart KOReader.

### Kobo

1. Connect your Kobo to your computer via USB.
2. key to seeing the folder: **Make sure "Show hidden files" is enabled on your computer**, as the folder starts with a dot.
3. Navigate to `.adds/koreader/plugins/`.
4. Copy the `lektr.koplugin` folder from this directory into `.adds/koreader/plugins/`.
5. Eject/Disconnect your device and restart KOReader.

### Android

On Android, accessing the data folder can be tricky due to permission restrictions in newer Android versions.

1. Use a file manager that can access internal storage (e.g., Mixplorer, Solid Explorer) or connect to a PC.
2. Navigate to the KOReader folder, usually located at `/koreader/` in your internal storage.
3. Go into the `plugins/` directory.
4. Copy the `lektr.koplugin` folder into `plugins/`.
5. Restart KOReader.

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
