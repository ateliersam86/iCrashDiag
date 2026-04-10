#!/usr/bin/env python3
"""
iCrashDiag — iPhone Crash Log Analyzer
Outil de diagnostic pour techniciens réparateurs
"""

import customtkinter as ctk
import tkinter as tk
from tkinter import filedialog, messagebox
import json
import os
import re
import subprocess
import threading
from datetime import datetime
from collections import Counter, defaultdict
from pathlib import Path

# ============================================================
# Theme
# ============================================================

ctk.set_appearance_mode("dark")
ctk.set_default_color_theme("blue")

COLORS = {
    "bg": "#1a1a2e",
    "bg2": "#16213e",
    "card": "#1f2937",
    "accent": "#D84D2B",
    "green": "#22c55e",
    "yellow": "#eab308",
    "red": "#ef4444",
    "text": "#e2e8f0",
    "muted": "#94a3b8",
    "border": "#334155",
}

# ============================================================
# Crash Parser
# ============================================================

KNOWN_PATTERNS = {
    "mic1": {
        "search": ["mic1", "microphone"],
        "title": "Capteur thermique microphone (mic1)",
        "component": "Nappe Lightning / connecteur dock",
        "severity": "hardware",
        "description": "Le capteur thermique du microphone inférieur ne répond plus.",
        "diagnosis": (
            "85% → Nappe Lightning HS (micro inférieur soudé dessus)\n"
            "10% → Carte mère : codec audio Cirrus Logic, connecteur FPC, trace rompue\n"
            "5% → Résistance NTC dessoudée sur la carte mère"
        ),
        "fix": (
            "1. Remplacer la nappe Lightning (pièce avec NTC, pas cheap)\n"
            "2. Si persiste → inspecter connecteur FPC dock à la binoculaire\n"
            "3. Si persiste → codec audio Cirrus Logic (micro-soudure BGA)"
        ),
        "tests": (
            "• Mémo vocal → micro du bas fonctionne ?\n"
            "• Appel haut-parleur → son capté ?\n"
            "• Brancher nappe Lightning connue bonne → panics arrêtent ?"
        ),
    },
    "thermalmonitord": {
        "search": ["thermalmonitord", "thermal watchdog"],
        "title": "Watchdog thermique (thermalmonitord)",
        "component": "Capteur thermique / carte mère",
        "severity": "hardware",
        "description": "Le daemon de surveillance thermique ne répond plus au watchdog kernel.",
        "diagnosis": (
            "Capteur thermique déconnecté ou défaillant.\n"
            "Vérifier quel capteur est manquant dans le panic string."
        ),
        "fix": (
            "1. Identifier le capteur manquant (Missing sensor: xxx)\n"
            "2. Remplacer le composant associé\n"
            "3. Si capteur sur carte mère → micro-soudure"
        ),
        "tests": "• Vérifier tous les capteurs listés dans le panic log",
    },
    "gpu_hang": {
        "search": ["GPU Hang", "gpu hang", "AGXMetalA"],
        "title": "GPU Hang (processeur graphique)",
        "component": "Puce GPU / SoC",
        "severity": "hardware",
        "description": "Le GPU ne répond plus, provoquant un kernel panic.",
        "diagnosis": (
            "70% → Soudure BGA du SoC défaillante (micro-fissure)\n"
            "20% → Surchauffe GPU (pâte thermique, ventilation)\n"
            "10% → Bug driver iOS (tenter DFU restore)"
        ),
        "fix": (
            "1. DFU restore complet\n"
            "2. Si persiste → reball/reflow SoC (difficile)\n"
            "3. Souvent irréparable économiquement"
        ),
        "tests": "• Le téléphone chauffe anormalement ?\n• Artefacts graphiques ?",
    },
    "kernel_data_abort": {
        "search": ["kernel data abort", "data abort"],
        "title": "Kernel Data Abort",
        "component": "RAM / SoC",
        "severity": "hardware",
        "description": "Accès mémoire invalide au niveau kernel.",
        "diagnosis": (
            "60% → RAM défaillante (soudure BGA)\n"
            "30% → NAND Flash corrompue\n"
            "10% → Bug iOS (tenter DFU restore)"
        ),
        "fix": (
            "1. DFU restore complet\n"
            "2. Si persiste → remplacement RAM (micro-soudure BGA)\n"
            "3. Si NAND → remplacement NAND + programmation"
        ),
        "tests": "• Combien de panics par jour ? (>5 = sûrement hardware)",
    },
    "watchdog_backboardd": {
        "search": ["backboardd", "backboard watchdog"],
        "title": "Watchdog backboardd (écran/tactile)",
        "component": "Nappe écran / connecteur écran",
        "severity": "hardware",
        "description": "Le service d'affichage/tactile ne répond plus.",
        "diagnosis": (
            "80% → Nappe écran défaillante ou mal branchée\n"
            "15% → Connecteur FPC écran sur carte mère\n"
            "5% → Puce tactile (Meson)"
        ),
        "fix": (
            "1. Rebrancher / remplacer la nappe écran\n"
            "2. Inspecter connecteur FPC écran\n"
            "3. Si persiste → puce tactile"
        ),
        "tests": "• Écran tactile répond normalement ?\n• Ghost touch ?",
    },
    "watchdog_wifid": {
        "search": ["wifid", "wifi watchdog"],
        "title": "Watchdog WiFi (wifid)",
        "component": "Puce WiFi / Bluetooth",
        "severity": "hardware",
        "description": "Le service WiFi ne répond plus.",
        "diagnosis": (
            "70% → Puce WiFi/BT défaillante\n"
            "20% → Antenne WiFi déconnectée\n"
            "10% → Software (DFU restore)"
        ),
        "fix": (
            "1. DFU restore\n"
            "2. Vérifier antennes WiFi\n"
            "3. Reball puce WiFi"
        ),
        "tests": "• WiFi fonctionne ?\n• Bluetooth fonctionne ?",
    },
    "SEP": {
        "search": ["SEP panic", "Secure Enclave"],
        "title": "Secure Enclave Panic",
        "component": "SEP / SoC",
        "severity": "critical",
        "description": "Le Secure Enclave Processor a paniqué.",
        "diagnosis": "Problème critique SoC. Souvent irréparable.",
        "fix": "Remplacement carte mère.",
        "tests": "• Face ID / Touch ID fonctionne ?",
    },
}

IPHONE_MODELS = {
    "iPhone1,1": "iPhone 2G", "iPhone1,2": "iPhone 3G",
    "iPhone2,1": "iPhone 3GS", "iPhone3,1": "iPhone 4",
    "iPhone4,1": "iPhone 4S", "iPhone5,1": "iPhone 5",
    "iPhone5,2": "iPhone 5", "iPhone5,3": "iPhone 5c",
    "iPhone5,4": "iPhone 5c", "iPhone6,1": "iPhone 5s",
    "iPhone6,2": "iPhone 5s", "iPhone7,1": "iPhone 6 Plus",
    "iPhone7,2": "iPhone 6", "iPhone8,1": "iPhone 6s",
    "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE",
    "iPhone9,1": "iPhone 7", "iPhone9,2": "iPhone 7 Plus",
    "iPhone9,3": "iPhone 7", "iPhone9,4": "iPhone 7 Plus",
    "iPhone10,1": "iPhone 8", "iPhone10,2": "iPhone 8 Plus",
    "iPhone10,3": "iPhone X", "iPhone10,4": "iPhone 8",
    "iPhone10,5": "iPhone 8 Plus", "iPhone10,6": "iPhone X",
    "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
    "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
    "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro",
    "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE 2",
    "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
    "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
    "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
    "iPhone14,6": "iPhone SE 3", "iPhone14,7": "iPhone 14",
    "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
    "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15",
    "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro",
    "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,1": "iPhone 16 Pro",
    "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16",
    "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
}


def parse_ips_file(filepath):
    """Parse un fichier .ips et retourne les infos structurées."""
    try:
        with open(filepath, "r", errors="replace") as f:
            content = f.read()

        lines = content.strip().split("\n")
        if not lines:
            return None

        # Première ligne = metadata JSON
        try:
            meta = json.loads(lines[0])
        except json.JSONDecodeError:
            meta = {}

        # Deuxième partie = JSON du panic
        panic_data = {}
        try:
            rest = "\n".join(lines[1:])
            panic_data = json.loads(rest)
        except json.JSONDecodeError:
            pass

        bug_type = meta.get("bug_type", "")
        timestamp = meta.get("timestamp", "")
        os_version = meta.get("os_version", "")

        product = panic_data.get("product", "")
        model_name = IPHONE_MODELS.get(product, product)
        panic_string = panic_data.get("panicString", "")

        # Identifier le type de panic
        panic_type = "unknown"
        matched_pattern = None
        missing_sensors = []

        # Extraire les capteurs manquants
        sensor_match = re.search(r"Missing sensor\(s\):\s*(.+?)[\n\\]", panic_string)
        if sensor_match:
            missing_sensors = [s.strip() for s in sensor_match.group(1).split(",")]

        # Identifier le pattern
        for key, pattern in KNOWN_PATTERNS.items():
            for search_term in pattern["search"]:
                if search_term.lower() in panic_string.lower():
                    panic_type = key
                    matched_pattern = pattern
                    break
            if matched_pattern:
                break

        # Extraire le service fautif
        faulting_service = ""
        svc_match = re.search(
            r"no successful checkins from (\S+)", panic_string
        )
        if svc_match:
            faulting_service = svc_match.group(1)

        # Extraire les infos CPU
        cpu_caller = ""
        caller_match = re.search(r"cpu (\d+) caller (0x[\da-f]+)", panic_string)
        if caller_match:
            cpu_caller = f"CPU {caller_match.group(1)}, caller {caller_match.group(2)}"

        return {
            "file": os.path.basename(filepath),
            "filepath": filepath,
            "bug_type": bug_type,
            "timestamp": timestamp,
            "os_version": os_version,
            "product": product,
            "model_name": model_name,
            "panic_type": panic_type,
            "matched_pattern": matched_pattern,
            "panic_string": panic_string[:500],
            "full_panic_string": panic_string,
            "missing_sensors": missing_sensors,
            "faulting_service": faulting_service,
            "cpu_caller": cpu_caller,
        }
    except Exception as e:
        return {"file": os.path.basename(filepath), "error": str(e)}


def analyze_crashes(crash_list):
    """Analyse globale d'une liste de crashes parsés."""
    if not crash_list:
        return {}

    valid = [c for c in crash_list if "error" not in c]
    if not valid:
        return {"total": len(crash_list), "errors": len(crash_list)}

    # Stats par type
    type_counts = Counter(c["panic_type"] for c in valid)
    sensor_counts = Counter(s for c in valid for s in c.get("missing_sensors", []))
    service_counts = Counter(
        c["faulting_service"] for c in valid if c["faulting_service"]
    )

    # Timeline
    dates = []
    for c in valid:
        ts = c.get("timestamp", "")
        try:
            dt = datetime.strptime(ts.split(".")[0], "%Y-%m-%d %H:%M:%S")
            dates.append(dt)
        except (ValueError, IndexError):
            pass

    panics_per_day = Counter(d.strftime("%Y-%m-%d") for d in dates)

    # Période
    date_range = ""
    if dates:
        dates.sort()
        delta = (dates[-1] - dates[0]).days
        date_range = f"{dates[0].strftime('%d/%m')} → {dates[-1].strftime('%d/%m')} ({delta} jours)"

    # Fréquence
    avg_per_day = len(valid) / max((dates[-1] - dates[0]).days, 1) if len(dates) > 1 else len(valid)
    worst_day = max(panics_per_day.items(), key=lambda x: x[1]) if panics_per_day else ("", 0)

    # Modèle
    models = Counter(c["model_name"] for c in valid if c["model_name"])
    os_versions = Counter(c["os_version"] for c in valid if c["os_version"])

    # Pattern dominant
    dominant_type = type_counts.most_common(1)[0] if type_counts else ("unknown", 0)
    dominant_pattern = None
    if dominant_type[0] in KNOWN_PATTERNS:
        dominant_pattern = KNOWN_PATTERNS[dominant_type[0]]

    return {
        "total": len(crash_list),
        "valid": len(valid),
        "errors": len(crash_list) - len(valid),
        "type_counts": dict(type_counts),
        "sensor_counts": dict(sensor_counts),
        "service_counts": dict(service_counts),
        "panics_per_day": dict(panics_per_day),
        "date_range": date_range,
        "avg_per_day": round(avg_per_day, 1),
        "worst_day": worst_day,
        "models": dict(models),
        "os_versions": dict(os_versions),
        "dominant_type": dominant_type,
        "dominant_pattern": dominant_pattern,
    }


# ============================================================
# GUI
# ============================================================


class CrashCard(ctk.CTkFrame):
    """Card pour afficher un crash individuel."""

    def __init__(self, master, crash_data, click_callback=None, **kwargs):
        super().__init__(master, corner_radius=8, fg_color=COLORS["card"], **kwargs)

        self.crash = crash_data
        self.click_callback = click_callback

        severity_colors = {
            "hardware": COLORS["red"],
            "critical": "#dc2626",
            "software": COLORS["yellow"],
            "unknown": COLORS["muted"],
        }

        pattern = crash_data.get("matched_pattern", {})
        severity = pattern.get("severity", "unknown") if pattern else "unknown"
        color = severity_colors.get(severity, COLORS["muted"])

        # Indicateur couleur
        indicator = ctk.CTkFrame(self, width=4, corner_radius=2, fg_color=color)
        indicator.pack(side="left", fill="y", padx=(0, 8), pady=4)

        content = ctk.CTkFrame(self, fg_color="transparent")
        content.pack(side="left", fill="both", expand=True, padx=4, pady=6)

        # Titre
        title = pattern.get("title", crash_data.get("panic_type", "Inconnu")) if pattern else crash_data.get("panic_type", "Inconnu")
        title_label = ctk.CTkLabel(
            content, text=title, font=("SF Pro Display", 13, "bold"),
            text_color=COLORS["text"], anchor="w"
        )
        title_label.pack(fill="x")

        # Timestamp + modèle
        ts = crash_data.get("timestamp", "")[:19]
        model = crash_data.get("model_name", "")
        info_text = f"{ts}  •  {model}" if model else ts
        info_label = ctk.CTkLabel(
            content, text=info_text, font=("SF Pro Display", 11),
            text_color=COLORS["muted"], anchor="w"
        )
        info_label.pack(fill="x")

        # Sensors manquants
        sensors = crash_data.get("missing_sensors", [])
        if sensors:
            sensor_label = ctk.CTkLabel(
                content, text=f"Capteurs manquants : {', '.join(sensors)}",
                font=("SF Pro Display", 11), text_color=color, anchor="w"
            )
            sensor_label.pack(fill="x")

        # Bind click
        if click_callback:
            for widget in [self, indicator, content, title_label, info_label]:
                widget.bind("<Button-1>", lambda e: click_callback(crash_data))
                widget.configure(cursor="hand2")


class App(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("iCrashDiag — iPhone Crash Analyzer")
        self.geometry("1200x800")
        self.minsize(900, 600)

        self.crashes = []
        self.analysis = {}

        self._build_ui()

    def _build_ui(self):
        # Top bar
        topbar = ctk.CTkFrame(self, height=60, corner_radius=0, fg_color=COLORS["bg2"])
        topbar.pack(fill="x")
        topbar.pack_propagate(False)

        logo = ctk.CTkLabel(
            topbar, text="iCrashDiag",
            font=("SF Pro Display", 22, "bold"), text_color=COLORS["accent"]
        )
        logo.pack(side="left", padx=20)

        subtitle = ctk.CTkLabel(
            topbar, text="iPhone Crash Log Analyzer",
            font=("SF Pro Display", 13), text_color=COLORS["muted"]
        )
        subtitle.pack(side="left", padx=5)

        # Buttons
        btn_frame = ctk.CTkFrame(topbar, fg_color="transparent")
        btn_frame.pack(side="right", padx=20)

        self.btn_usb = ctk.CTkButton(
            btn_frame, text="Lire iPhone USB",
            command=self._pull_from_device, fg_color=COLORS["accent"],
            hover_color="#b5402a", font=("SF Pro Display", 13, "bold"),
            width=150, height=35
        )
        self.btn_usb.pack(side="left", padx=5)

        self.btn_folder = ctk.CTkButton(
            btn_frame, text="Ouvrir dossier",
            command=self._open_folder, fg_color=COLORS["border"],
            hover_color="#475569", font=("SF Pro Display", 13),
            width=130, height=35
        )
        self.btn_folder.pack(side="left", padx=5)

        # Status bar
        self.status_var = tk.StringVar(value="Prêt — Connectez un iPhone ou ouvrez un dossier de crash logs")
        status_bar = ctk.CTkLabel(
            self, textvariable=self.status_var,
            font=("SF Pro Display", 11), text_color=COLORS["muted"],
            anchor="w", height=25
        )
        status_bar.pack(fill="x", padx=20, pady=(5, 0))

        # Main content
        main = ctk.CTkFrame(self, fg_color="transparent")
        main.pack(fill="both", expand=True, padx=10, pady=5)

        # Left panel — crash list
        left = ctk.CTkFrame(main, width=400, fg_color="transparent")
        left.pack(side="left", fill="both", padx=5, pady=5)
        left.pack_propagate(False)

        # Summary card
        self.summary_frame = ctk.CTkFrame(left, corner_radius=10, fg_color=COLORS["card"], height=180)
        self.summary_frame.pack(fill="x", pady=(0, 8))
        self.summary_frame.pack_propagate(False)

        self.summary_label = ctk.CTkLabel(
            self.summary_frame, text="Aucune donnée\n\nConnectez un iPhone ou ouvrez un dossier",
            font=("SF Pro Display", 13), text_color=COLORS["muted"],
            justify="center"
        )
        self.summary_label.pack(expand=True)

        # Crash list
        list_header = ctk.CTkLabel(
            left, text="CRASH LOGS", font=("SF Pro Display", 11, "bold"),
            text_color=COLORS["muted"], anchor="w"
        )
        list_header.pack(fill="x", pady=(5, 2))

        self.crash_list_frame = ctk.CTkScrollableFrame(
            left, fg_color="transparent", corner_radius=8
        )
        self.crash_list_frame.pack(fill="both", expand=True)

        # Right panel — detail
        right = ctk.CTkFrame(main, fg_color="transparent")
        right.pack(side="right", fill="both", expand=True, padx=5, pady=5)

        self.detail_frame = ctk.CTkFrame(right, corner_radius=10, fg_color=COLORS["card"])
        self.detail_frame.pack(fill="both", expand=True)

        self.detail_content = ctk.CTkLabel(
            self.detail_frame,
            text="Sélectionnez un crash pour voir les détails\net le diagnostic",
            font=("SF Pro Display", 14), text_color=COLORS["muted"],
            justify="center"
        )
        self.detail_content.pack(expand=True)

    def _set_status(self, text):
        self.status_var.set(text)
        self.update_idletasks()

    def _pull_from_device(self):
        """Pull crash logs from connected iPhone via USB."""
        self._set_status("Recherche d'un iPhone connecté...")

        def _pull():
            try:
                result = subprocess.run(
                    ["idevice_id", "-l"], capture_output=True, text=True, timeout=10
                )
                devices = result.stdout.strip().split("\n")
                devices = [d for d in devices if d.strip()]

                if not devices:
                    self.after(0, lambda: self._set_status("Aucun iPhone détecté. Vérifiez la connexion USB."))
                    self.after(0, lambda: messagebox.showwarning(
                        "Pas d'iPhone", "Aucun iPhone détecté.\n\nVérifiez :\n• Câble USB branché\n• iPhone déverrouillé\n• 'Faire confiance' accepté"
                    ))
                    return

                # Get device info
                info_result = subprocess.run(
                    ["ideviceinfo", "-k", "ProductType"], capture_output=True, text=True, timeout=10
                )
                device_type = info_result.stdout.strip()

                name_result = subprocess.run(
                    ["ideviceinfo", "-k", "DeviceName"], capture_output=True, text=True, timeout=10
                )
                device_name = name_result.stdout.strip()

                self.after(0, lambda: self._set_status(
                    f"iPhone détecté : {device_name} ({device_type}) — Extraction des crash logs..."
                ))

                # Pull crash logs
                tmp_dir = os.path.expanduser("~/Desktop/iCrashDiag-Export")
                os.makedirs(tmp_dir, exist_ok=True)

                pull_result = subprocess.run(
                    ["idevicecrashreport", "-e", tmp_dir],
                    capture_output=True, text=True, timeout=120
                )

                self.after(0, lambda: self._load_folder(tmp_dir))

            except FileNotFoundError:
                self.after(0, lambda: self._set_status("libimobiledevice non installé"))
                self.after(0, lambda: messagebox.showerror(
                    "Erreur", "libimobiledevice n'est pas installé.\n\nbrew install libimobiledevice"
                ))
            except subprocess.TimeoutExpired:
                self.after(0, lambda: self._set_status("Timeout — l'iPhone ne répond pas"))
            except Exception as e:
                self.after(0, lambda: self._set_status(f"Erreur : {e}"))

        threading.Thread(target=_pull, daemon=True).start()

    def _open_folder(self):
        folder = filedialog.askdirectory(title="Sélectionner le dossier de crash logs")
        if folder:
            self._load_folder(folder)

    def _load_folder(self, folder):
        self._set_status(f"Chargement des fichiers depuis {folder}...")

        def _parse():
            ips_files = list(Path(folder).glob("*.ips"))
            panic_files = [f for f in ips_files if "panic" in f.name.lower()]
            other_files = [f for f in ips_files if "panic" not in f.name.lower()]

            # Priorité aux panics, puis les autres
            all_files = panic_files + other_files

            crashes = []
            for i, f in enumerate(all_files):
                result = parse_ips_file(str(f))
                if result:
                    crashes.append(result)
                if i % 20 == 0:
                    self.after(0, lambda i=i: self._set_status(
                        f"Parsing... {i}/{len(all_files)} fichiers"
                    ))

            # Trier par date
            crashes.sort(key=lambda c: c.get("timestamp", ""), reverse=True)
            self.crashes = crashes
            self.analysis = analyze_crashes(crashes)

            self.after(0, self._update_ui)

        threading.Thread(target=_parse, daemon=True).start()

    def _update_ui(self):
        a = self.analysis
        if not a:
            return

        # Update summary
        for w in self.summary_frame.winfo_children():
            w.destroy()

        summary_inner = ctk.CTkFrame(self.summary_frame, fg_color="transparent")
        summary_inner.pack(fill="both", expand=True, padx=15, pady=12)

        # Title
        ctk.CTkLabel(
            summary_inner, text="DIAGNOSTIC",
            font=("SF Pro Display", 11, "bold"), text_color=COLORS["muted"], anchor="w"
        ).pack(fill="x")

        # Total + severity
        dominant = a.get("dominant_pattern")
        if dominant:
            severity_text = {
                "hardware": "HARDWARE",
                "critical": "CRITIQUE",
                "software": "SOFTWARE",
            }.get(dominant.get("severity", ""), "INCONNU")
            severity_color = {
                "hardware": COLORS["red"],
                "critical": "#dc2626",
                "software": COLORS["yellow"],
            }.get(dominant.get("severity", ""), COLORS["muted"])

            header_frame = ctk.CTkFrame(summary_inner, fg_color="transparent")
            header_frame.pack(fill="x", pady=(4, 0))

            ctk.CTkLabel(
                header_frame, text=f"{a['valid']} panics",
                font=("SF Pro Display", 28, "bold"), text_color=COLORS["text"], anchor="w"
            ).pack(side="left")

            badge = ctk.CTkLabel(
                header_frame, text=f" {severity_text} ",
                font=("SF Pro Display", 11, "bold"), text_color="#fff",
                fg_color=severity_color, corner_radius=4
            )
            badge.pack(side="left", padx=10)

            ctk.CTkLabel(
                summary_inner, text=dominant.get("title", ""),
                font=("SF Pro Display", 14, "bold"), text_color=COLORS["accent"], anchor="w"
            ).pack(fill="x", pady=(4, 0))

            ctk.CTkLabel(
                summary_inner, text=f"Composant : {dominant.get('component', '')}",
                font=("SF Pro Display", 12), text_color=COLORS["text"], anchor="w"
            ).pack(fill="x")
        else:
            ctk.CTkLabel(
                summary_inner, text=f"{a.get('valid', 0)} crashes analysés",
                font=("SF Pro Display", 22, "bold"), text_color=COLORS["text"], anchor="w"
            ).pack(fill="x")

        # Stats line
        stats_text = f"{a.get('date_range', '')}  •  ~{a.get('avg_per_day', 0)}/jour"
        worst = a.get("worst_day", ("", 0))
        if worst[1] > 0:
            stats_text += f"  •  Pire : {worst[1]} le {worst[0]}"
        ctk.CTkLabel(
            summary_inner, text=stats_text,
            font=("SF Pro Display", 11), text_color=COLORS["muted"], anchor="w"
        ).pack(fill="x", pady=(2, 0))

        # Model + OS
        models = a.get("models", {})
        os_versions = a.get("os_versions", {})
        if models:
            model_text = ", ".join(f"{m} ({c})" for m, c in models.most_common(3)) if isinstance(models, Counter) else ", ".join(models.keys())
            ctk.CTkLabel(
                summary_inner, text=f"Appareil : {model_text}",
                font=("SF Pro Display", 11), text_color=COLORS["muted"], anchor="w"
            ).pack(fill="x")

        # Sensors
        sensors = a.get("sensor_counts", {})
        if sensors:
            sensor_text = ", ".join(f"{s} ({c}x)" for s, c in sorted(sensors.items(), key=lambda x: -x[1]))
            ctk.CTkLabel(
                summary_inner, text=f"Capteurs manquants : {sensor_text}",
                font=("SF Pro Display", 11), text_color=COLORS["red"], anchor="w"
            ).pack(fill="x")

        # Update crash list
        for w in self.crash_list_frame.winfo_children():
            w.destroy()

        for crash in self.crashes[:200]:
            if "error" in crash:
                continue
            card = CrashCard(
                self.crash_list_frame, crash,
                click_callback=self._show_detail
            )
            card.pack(fill="x", pady=2)

        self._set_status(f"{a['valid']} crashes analysés — {a.get('errors', 0)} erreurs de parsing")

        # Show diagnosis in detail panel if pattern found
        if dominant:
            self._show_diagnosis(dominant, a)

    def _show_diagnosis(self, pattern, analysis):
        """Afficher le diagnostic global dans le panel de droite."""
        for w in self.detail_frame.winfo_children():
            w.destroy()

        scroll = ctk.CTkScrollableFrame(self.detail_frame, fg_color="transparent")
        scroll.pack(fill="both", expand=True, padx=15, pady=15)

        ctk.CTkLabel(
            scroll, text="DIAGNOSTIC",
            font=("SF Pro Display", 12, "bold"), text_color=COLORS["muted"], anchor="w"
        ).pack(fill="x", pady=(0, 5))

        ctk.CTkLabel(
            scroll, text=pattern.get("title", ""),
            font=("SF Pro Display", 20, "bold"), text_color=COLORS["text"], anchor="w",
            wraplength=600
        ).pack(fill="x")

        ctk.CTkLabel(
            scroll, text=pattern.get("description", ""),
            font=("SF Pro Display", 13), text_color=COLORS["muted"], anchor="w",
            wraplength=600, justify="left"
        ).pack(fill="x", pady=(4, 12))

        # Sections
        sections = [
            ("Probabilités", pattern.get("diagnosis", ""), COLORS["text"]),
            ("Réparation", pattern.get("fix", ""), COLORS["green"]),
            ("Tests à faire", pattern.get("tests", ""), COLORS["yellow"]),
        ]

        for title, content, color in sections:
            if not content:
                continue

            sep = ctk.CTkFrame(scroll, height=1, fg_color=COLORS["border"])
            sep.pack(fill="x", pady=8)

            ctk.CTkLabel(
                scroll, text=title,
                font=("SF Pro Display", 13, "bold"), text_color=color, anchor="w"
            ).pack(fill="x")

            ctk.CTkLabel(
                scroll, text=content,
                font=("SF Mono", 12), text_color=COLORS["text"], anchor="w",
                wraplength=600, justify="left"
            ).pack(fill="x", pady=(2, 4))

        # Timeline
        panics_per_day = analysis.get("panics_per_day", {})
        if panics_per_day:
            sep = ctk.CTkFrame(scroll, height=1, fg_color=COLORS["border"])
            sep.pack(fill="x", pady=8)

            ctk.CTkLabel(
                scroll, text="Timeline (panics/jour)",
                font=("SF Pro Display", 13, "bold"), text_color=COLORS["muted"], anchor="w"
            ).pack(fill="x")

            max_count = max(panics_per_day.values())
            for date in sorted(panics_per_day.keys()):
                count = panics_per_day[date]
                bar_width = int((count / max_count) * 300)

                row = ctk.CTkFrame(scroll, fg_color="transparent", height=22)
                row.pack(fill="x", pady=1)
                row.pack_propagate(False)

                ctk.CTkLabel(
                    row, text=date, font=("SF Mono", 11),
                    text_color=COLORS["muted"], width=90, anchor="w"
                ).pack(side="left")

                bar_color = COLORS["green"]
                if count > 10:
                    bar_color = COLORS["red"]
                elif count > 5:
                    bar_color = COLORS["yellow"]

                bar = ctk.CTkFrame(row, width=max(bar_width, 4), height=14, corner_radius=3, fg_color=bar_color)
                bar.pack(side="left", padx=(4, 8))

                ctk.CTkLabel(
                    row, text=str(count), font=("SF Mono", 11),
                    text_color=COLORS["text"], anchor="w"
                ).pack(side="left")

    def _show_detail(self, crash):
        """Afficher le détail d'un crash spécifique."""
        for w in self.detail_frame.winfo_children():
            w.destroy()

        scroll = ctk.CTkScrollableFrame(self.detail_frame, fg_color="transparent")
        scroll.pack(fill="both", expand=True, padx=15, pady=15)

        # Header
        pattern = crash.get("matched_pattern")
        title = pattern.get("title", crash.get("panic_type", "Inconnu")) if pattern else crash.get("panic_type", "Inconnu")

        ctk.CTkLabel(
            scroll, text=title,
            font=("SF Pro Display", 18, "bold"), text_color=COLORS["accent"], anchor="w",
            wraplength=600
        ).pack(fill="x")

        # Info
        info_items = [
            ("Fichier", crash.get("file", "")),
            ("Date", crash.get("timestamp", "")),
            ("Appareil", f"{crash.get('model_name', '')} ({crash.get('product', '')})"),
            ("iOS", crash.get("os_version", "")),
            ("Service fautif", crash.get("faulting_service", "")),
            ("CPU", crash.get("cpu_caller", "")),
            ("Capteurs manquants", ", ".join(crash.get("missing_sensors", []))),
        ]

        for label, value in info_items:
            if not value:
                continue
            row = ctk.CTkFrame(scroll, fg_color="transparent")
            row.pack(fill="x", pady=1)

            ctk.CTkLabel(
                row, text=f"{label}:", font=("SF Pro Display", 12, "bold"),
                text_color=COLORS["muted"], width=140, anchor="w"
            ).pack(side="left")

            ctk.CTkLabel(
                row, text=value, font=("SF Pro Display", 12),
                text_color=COLORS["text"], anchor="w"
            ).pack(side="left", fill="x", expand=True)

        # Diagnostic si pattern connu
        if pattern:
            sep = ctk.CTkFrame(scroll, height=1, fg_color=COLORS["border"])
            sep.pack(fill="x", pady=10)

            ctk.CTkLabel(
                scroll, text="DIAGNOSTIC",
                font=("SF Pro Display", 12, "bold"), text_color=COLORS["green"], anchor="w"
            ).pack(fill="x")

            ctk.CTkLabel(
                scroll, text=pattern.get("diagnosis", ""),
                font=("SF Mono", 12), text_color=COLORS["text"], anchor="w",
                wraplength=600, justify="left"
            ).pack(fill="x", pady=(2, 8))

            ctk.CTkLabel(
                scroll, text="RÉPARATION",
                font=("SF Pro Display", 12, "bold"), text_color=COLORS["accent"], anchor="w"
            ).pack(fill="x")

            ctk.CTkLabel(
                scroll, text=pattern.get("fix", ""),
                font=("SF Mono", 12), text_color=COLORS["text"], anchor="w",
                wraplength=600, justify="left"
            ).pack(fill="x", pady=(2, 8))

        # Panic string brut
        sep2 = ctk.CTkFrame(scroll, height=1, fg_color=COLORS["border"])
        sep2.pack(fill="x", pady=10)

        ctk.CTkLabel(
            scroll, text="PANIC STRING (brut)",
            font=("SF Pro Display", 12, "bold"), text_color=COLORS["muted"], anchor="w"
        ).pack(fill="x")

        panic_text = ctk.CTkTextbox(
            scroll, height=300, font=("SF Mono", 11),
            fg_color=COLORS["bg"], text_color=COLORS["text"],
            corner_radius=8
        )
        panic_text.pack(fill="x", pady=(4, 0))
        panic_text.insert("1.0", crash.get("full_panic_string", "N/A"))
        panic_text.configure(state="disabled")


if __name__ == "__main__":
    app = App()
    app.mainloop()
