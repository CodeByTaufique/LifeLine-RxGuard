# 🏥 LifeLine RxGuard

**LifeLine** is a high-performance, lightweight Pharmacy Management System (PMS) engineered entirely in **Bash Shell Scripting**. By leveraging **Zenity** for a sophisticated GTK+ graphical interface and a structured **Flat-File Database architecture**, LifeLine delivers a robust management suite without the overhead of heavy SQL servers or runtime environments.

---

## 🏗 System Architecture

LifeLine operates on a **Modular Scripting Design**, separating the business logic from the presentation layer.

* **Frontend:** Zenity-driven dynamic dialogs (Forms, Lists, Progress Bars)
* **Backend:** POSIX-compliant shell utilities (`grep`, `sed`, `awk`) for high-speed data parsing
* **Storage:** ACID-inspired flat-file transactions stored in `.txt` and `.csv` formats
* **Security:** Multi-level access control (MAC) and cryptographic-lite integrity checks

---

## 🚀 Core Functionalities

### 🛡️ Secure Authentication & Governance

* **Role-Based Access Control (RBAC):** Distinct permission tiers for **Pharmacists** (Administrative) and **Staff** (Operational)
* **Encrypted Credentials:** Secure storage of user hashes within `systemUsers.txt`
* **Comprehensive Auditing:** Real-time logging of every transaction and system change in `auditTrail.txt` for HIPAA-style compliance tracking

### 💊 Advanced Inventory Control

* **Dynamic Stock Engine:** Real-time CRUD operations for medicine inventory
* **Intelligent Alerting:** Automated visual triggers for low-stock and upcoming expiration dates
* **Restricted Substance Protocol:** Specialized workflow for high-risk medicine requests requiring secondary authorization

### 🩸 Blood Bank & Donor Registry

* **Inventory Tracking:** Real-time monitoring of blood reserves
* **Donor Lifecycle Management:** Detailed contact history and eligibility tracking

### 🧾 Financial Intelligence & Billing

* **Automated Ledger:** Instant invoice generation based on real-time inventory pricing
* **Digital Signatures:** Unique staff identifiers appended to every bill for non-repudiation
* **Exportable Reports:** Generate financial summaries and patient billing history

---

## 🛠 Tech Stack & Dependencies

| Layer | Technology | Purpose |
| --- | --- | --- |
| **Logic** | Bash Shell (v5.0+) | Core processing and automation |
| **Interface** | Zenity / GTK+ | User forms, alerts, and data tables |
| **Data** | Flat-File (Delimited) | High-speed, zero-dependency storage |
| **Utilities** | `coreutils` | Data manipulation (`sed`, `awk`, `grep`) |
| **Archive** | `zip` | Automated database backups |

---

## 💻 Installation & Deployment

### 1. Environment Preparation

Ensure your Linux distribution has the necessary GTK components:

```bash
sudo apt update && sudo apt install zenity -y
````

### 2. Repository Setup

```bash
git clone https://github.com/CodeByTaufique/LifeLine.git
cd LifeLine
```

### 3. Permissions & Execution

```bash
chmod +x lifeLine.sh
./lifeLine.sh
```

> **First-Run Configuration:** Upon initial execution, LifeLine triggers the **Admin Initialization Wizard**. This sets the master Pharmacist credentials. Do not lose these credentials, as they are required to provision Staff accounts.

---
## 🔐 Authentication & Default Access

For immediate system setup, use the following pre-configured credentials.

> ⚠️ **Security Note:** It is highly recommended to use these credentials during your first session. Otherwise you can Login if you clone this project. If you copy the code only then you have to manually input all Medicine name & Blood Donors.

### 👤 User Roles & Credentials

| User Role               | Username    | Default Password        | Permissions                              |
|-------------------------|------------|-------------------------|------------------------------------------|
| Pharmacist (Admin)      | Taufique   | 1234                    | Full Access / Staff Management           |
| Staff Member            | Akash      | 1234                    | Inventory & Dispensing Only              |

---

## 🛡️ Cloning & Security Protocol

To maintain enterprise-grade security for **LifeLine RxGuard**, the system employs a **"Pharmacist-First" Security Model**.

### 🔒 Repository Cloning Protection

If this project is cloned to a new environment:

- The system remains in a **Locked State**
- Access to the **Meds Control Dashboard** is restricted
- A valid **Pharmacist login** must be verified before full access is granted

---

### 🏗️ Administrative Gatekeeping

Only a user authenticated with the **Pharmacist password** can:

- Add, Remove, or Modify Staff accounts  
- Access the Controlled Substances database  
- Generate and view sensitive Audit Logs  

---

### 👥 Staff Provisioning Policy

- Staff members **cannot self-register**
- New accounts must be manually created via: **Pharmacist**



## 📂 Data Schema (Filesystem)

LifeLine maintains a structured directory `lifeLineData/` to ensure data integrity:

| File                 | Description                                             |
| -------------------- | ------------------------------------------------------- |
| `medsInventory.txt`  | Primary medicine records (ID, Name, Qty, Price, Expiry) |
| `bloodInventory.txt` | Unit counts for all major blood groups                  |
| `systemUsers.txt`    | UID, Role, and Hashed Passwords                         |
| `auditTrail.txt`     | Chronological system event logs                         |
| `patientBills.txt`   | Immutable billing history                               |
| `.activeEmergency`   | Temporary buffer for pending restricted requests        |
| `backUps/`           | Archived database snapshots                             |

---

## 📊 Maintenance & Troubleshooting

| Symptom               | Diagnosis                   | Resolution                                 |
| --------------------- | --------------------------- | ------------------------------------------ |
| **UI Non-Responsive** | Missing X11/Wayland display | Ensure you are in a GUI session            |
| **Data Corruption**   | Manual file editing         | Restore from `backUps/` directory          |
| **Permission Denied** | Script lacks execution bit  | Run `chmod 755 lifeLine.sh`                |
| **Empty Lists**       | Pathing error               | Run script from the root project directory |

---

## 👤 Author

**Taufique**
*Clean Code Enthusiast | Bash Systems Architect*

---

## 📜 License

This project is **educational and open-source**, intended for learning and demonstration purposes.
It showcases **efficient Bash scripting**, **GUI integration with Zenity**, and **flat-file database handling**.
