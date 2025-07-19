# AgeLapse 

![AgeLapse Logo](https://i.imgur.com/lfC2Y4y.png)

**AgeLapse** is a comprehensive tool for creating, stabilizing and exporting aging timelapses, i.e. "selfie a day" projects.  

This is the Flutter build of AgeLapse. This README serves mostly to help developers run AgeLapse in a development environment.

## For Non-Devs:

Not a developer and just looking to install the app? Click here: https://agelapse.com

## Development Setup (AgeLapse Desktop)

### Prerequisites

1. **Clone the repository**  
   ```sh
   git clone https://github.com/hugocornellier/agelapse
   ```

2. **Set working directory to `agelapse-desktop`**  
   ```sh
   cd agelapse/agelapse-desktop
   ```

3. **Configure the Python environment**  
   - **Ensure** you have **Python 3.10.11** installed. (NOTE: You must use Python 3.10.11):  
     ```sh
     python3 --version  # should output Python 3.10.11
     ```  
   - **Create and activate** a new virtual environment:  
     ```sh
     python3 -m venv .venv
     source .venv/bin/activate    # On Windows: .venv\Scripts\activate
     ```  
   - **Install** the project dependencies (select the file matching your platform):  
     ```sh
     pip install -r requirements/requirements-<platform>.txt
     ```  
     Replace `<platform>` with `mac-arm64`, `mac-x86_64`, or `windows`.

4. **Run the application**  
   ```sh
   python main.py
   ```

5. **Build a distributable** *(optional)*  
   To generate a standalone executable, run PyInstaller with the appropriate spec file:  
   ```sh
   pyinstaller spec/macos-arm64.spec    # macOS ARM64
   pyinstaller spec/macos-x86_64.spec   # macOS x86_64
   pyinstaller spec/windows.spec        # Windows
   ```