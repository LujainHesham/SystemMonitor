# PC Health System Monitoring Tool

![Docker](https://img.shields.io/badge/Docker-Enabled-blue)
![Bash](https://img.shields.io/badge/Bash-Scripting-green)
![WSL2](https://img.shields.io/badge/WSL2-Compatible-purple)
![Linux](https://img.shields.io/badge/Linux-System_Admin-orange)
![PowerShell](https://img.shields.io/badge/PowerShell-Automation-blueviolet)

**A Cross-Platform System Monitoring Solution**  
*Academic project demonstrating Windows-Linux integration using Docker and WSL2*

## 📋 Project Overview

This is a university project for our **Operating Systems course** that creates a system monitoring tool bridging Windows and Linux environments. It demonstrates practical application of OS concepts through:

- **Cross-platform integration** between Windows host and Linux container
- **Containerization** with Docker for reproducible environments
- **Automated reporting** with HTML generation
- **Real-time telemetry collection** from multiple sources

## 🎓 Learning Objectives & Skills Demonstrated

### **Technical Skills Gained**
- **Bash Scripting**: System monitoring, data parsing, and automation
- **PowerShell**: Windows system metrics collection and export
- **Docker & Containerization**: Image building, volume mounting, environment variables
- **WSL2 Configuration**: Windows-Linux interoperability
- **JSON/CSV Processing**: Data extraction and transformation with `jq`
- **Web Technologies**: HTML/CSS/JavaScript for report generation
- **System Administration**: CPU, memory, disk, and network monitoring

### **Operating Systems Concepts Applied**
- Process management and system calls
- Filesystem interactions and I/O operations
- Memory management and resource monitoring
- Inter-process communication (via files/JSON)
- Virtualization and container concepts

## 🏗️ System Architecture

### **Data Flow**
```
Windows Host (WSL2) → Docker Container → HTML Report
    ↓                      ↓                 ↓
HWiNFO64 CSV        Ubuntu Monitoring    Browser View
PowerShell JSON     Script Execution
```

### **Monitoring Components**
| Component | Data Source | Metrics Collected |
|-----------|-------------|-------------------|
| **CPU** | `/proc/stat`, `lscpu` | Usage %, model, cores, load |
| **Memory** | `free` | Usage, swap, percentages |
| **Disk** | `df`, PowerShell | Space, health status |
| **Network** | `ip`, `ss` | Interfaces, connections |
| **Temperature** | HWiNFO64 CSV | CPU/GPU temperatures |
| **GPU** | PowerShell WMI | Adapter info, utilization |

## 📁 Project Structure

```
SystemMonitor/
├── docker/                    # Container configuration
│   ├── Dockerfile            # Ubuntu with tools
│   └── docker-compose.yml    # Service definition
├── scripts/
│   └── monitor.sh            # Main monitoring script
├── reports/                   # Generated reports
│   ├── assets/               # CSS/JS for HTML
│   ├── system_report_*.html  # Individual reports
│   └── index.html            # Report index
└── README.md                # Documentation
```

## 🚀 Quick Setup for Reviewers

To understand the project structure:

```bash
# View the main monitoring script (core logic)
head -50 scripts/monitor.sh

# Check Docker configuration
cat docker/docker-compose.yml

# See a sample report structure
ls -la reports/  # If reports exist
```

## 🔧 Technical Implementation

### **Key Features**
1. **Cross-Platform Monitoring**: Combines Linux container metrics with Windows host metrics
2. **Automated HTML Reports**: Generates styled reports with collapsible sections
3. **Error Handling**: Graceful degradation when components are unavailable
4. **Configuration**: Environment variables for easy customization

### **Integration Challenges Solved**
- CSV delimiter detection for different regional settings
- JSON schema adaptation for varying PowerShell outputs
- File path conversion between Windows and Linux
- Volume mounting for data sharing between host and container

## 🎯 Project Requirements Met

This project fulfills our Operating Systems course requirements by demonstrating:

1. **System Programming**: Direct interaction with `/proc`, system utilities
2. **Process Management**: Script execution, timing, scheduling
3. **File I/O**: Reading/writing CSV, JSON, HTML files
4. **Memory Concepts**: Monitoring usage, swap, and allocation
5. **Networking**: Interface monitoring and connection tracking
6. **Virtualization**: Container isolation and resource management

## 📚 Academic Context

**Course:** Operating Systems (5th Semester)  
**Institution:** Arab Academy for Science, Technology & Maritime Transport (AASTMT)  
**Duration:** 2-week project  
**Team Size:** 3 students  

## 👥 Team Contributions & Roles

**Project Team:**
- **Lujain Hesham** (Me): Bash scripting, system monitoring logic, core architecture
- **Nour Mohamed**: Docker configuration, container orchestration, deployment
- **Hala Mohamed**: HTML/CSS reporting, documentation, testing

**My Primary Responsibilities:**
- Developed the 500+ line `monitor.sh` Bash script
- Implemented system metric collection (CPU, memory, disk, network)
- Created CSV/JSON parsing logic for Windows telemetry
- Designed the HTML report generation system
- Set up WSL2-Linux integration patterns

## 📈 What We Learned

### **Technical Takeaways**
- Practical experience with Docker and containerization
- Real-world Bash scripting for system administration
- Cross-platform development challenges and solutions
- Importance of error handling and logging
- Automated reporting and data visualization

### **Team Collaboration**
- Version control with Git
- Documentation and code commenting
- Problem-solving through research and experimentation
- Dividing complex tasks into manageable components

## 🔍 For Technical Reviewers

This project demonstrates our ability to:
- Apply theoretical OS concepts to practical problems
- Learn and integrate multiple technologies
- Write maintainable, documented code
- Work collaboratively on a technical project
- Research solutions to technical challenges

## 🏆 Project Outcomes

- Successfully created a working monitoring tool
- Gained hands-on experience with industry-relevant tools
- Developed problem-solving skills for system integration
- Created comprehensive documentation
- Produced a portfolio-worthy project

---

## 📞 Contact

**Team Members:**
- Lujain Hesham - [GitHub](https://github.com/LujainHesham)
- Nour Mohamed - [GitHub](https://github.com/NourMohamed)
- Hala Mohamed - [GitHub](https://github.com/HalaMohamed)

**Project Repository:**  
[https://github.com/LujainHesham/PC-Health-Monitoring](https://github.com/LujainHesham/PC-Health-Monitoring)

---

*This project was developed as part of our Operating Systems coursework at AASTMT. It represents our learning journey in system programming, containerization, and cross-platform development.*

---



It tells recruiters: "We're students who can learn quickly, work in teams, and apply technical concepts to real problems" - which is exactly what they want to see from university candidates.

Would you like me to adjust any part to better reflect your actual experience or team dynamics?
