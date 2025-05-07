# Backup Proxmox a OneDrive con Rclone

Este proyecto contiene un script de shell (bash) diseñado para ejecutarse en un servidor Proxmox VE. Su propósito es automatizar la copia de seguridad de los respaldos VZDump locales (generados por Proxmox) a un almacenamiento en la nube de Microsoft OneDrive utilizando la herramienta rclone.

## Características Principales

- Se ejecuta desde cron (idealmente protegido con flock para evitar ejecuciones concurrentes)
- Escanea un directorio local especificado donde Proxmox guarda los respaldos finales
- Para cada archivo de respaldo de datos (.vma.zst, .tar.zst, etc.), verifica la existencia de su archivo .log correspondiente como señal de que el respaldo de Proxmox para esa VM/CT ha finalizado
- Si el .log existe, utiliza rclone copyto para copiar el archivo de datos, el archivo .log y el archivo .notes (si existe) a la carpeta designada en OneDrive
- Utiliza la opción --ignore-existing de rclone para evitar re-transferir archivos sin cambios
- Genera un archivo de log (/var/log/rclone_proxmox_checklog_onedrive.log) para registrar su actividad

## Contenido del Repositorio

- `backup_proxmox_to_onedrive.sh`: Script principal para la copia de respaldos
- `rclone-proxmox-backup`: Configuración recomendada para logrotate (debe colocarse en `/etc/logrotate.d/` en el servidor Proxmox)
- `.gitignore`: Asegura que archivos sensibles o innecesarios no se suban al repositorio

## Requisitos Previos

1. Servidor Proxmox VE con respaldos configurados
2. Rclone instalado y configurado con acceso a OneDrive
3. Permisos adecuados para ejecutar el script y acceder a los directorios de respaldo

## Instalación

1. Clonar este repositorio en el servidor Proxmox:
   ```
   git clone https://github.com/[tu-usuario]/backup-proxmox-onedrive-rclone.git
   ```

2. Ajustar la configuración en el script según tu entorno:
   - `LOCAL_BACKUP_DIR`: Directorio donde Proxmox guarda los respaldos
   - `RCLONE_REMOTE_NAME`: Nombre del "remote" de rclone configurado para OneDrive
   - `ONEDRIVE_DEST_FOLDER`: Carpeta de destino en OneDrive

3. Hacer el script ejecutable:
   ```
   chmod +x backup_proxmox_to_onedrive.sh
   ```

4. Instalar la configuración de logrotate:
   ```
   sudo cp rclone-proxmox-backup /etc/logrotate.d/
   ```

5. Configurar tarea cron (ejemplo para ejecutar cada hora):
   ```
   crontab -e
   ```
   Añadir:
   ```
   0 * * * * /usr/bin/flock -n /tmp/proxmox_onedrive_backup.lock /ruta/al/backup_proxmox_to_onedrive.sh
   ```

## Notas sobre Seguridad

- **IMPORTANTE**: Nunca subas tu archivo `rclone.conf` o cualquier token/secreto al repositorio
- La configuración `.gitignore` ya está preparada para evitar esto
- Asegúrate de proteger adecuadamente el script en tu servidor Proxmox

## Soporte y Contribuciones

Si encuentras algún problema o tienes sugerencias de mejora, por favor abre un issue en el repositorio. 