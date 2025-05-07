#!/bin/bash

###############################################################################
# Script para copiar respaldos de Proxmox a OneDrive usando rclone.
#
# VERSIÓN CON VERIFICACIÓN DE ARCHIVO .LOG
#
# Itera sobre los archivos de datos de respaldo en el directorio local.
# Para cada archivo de datos, verifica si existe su archivo .log correspondiente.
# Si el .log existe, copia el archivo de datos, el .log y el .notes (si existe)
# a una carpeta única en OneDrive.
# Usa --ignore-existing para no re-subir archivos idénticos.
# Incluye logging básico.
###############################################################################

# --- Configuración - ¡AJUSTA ESTOS VALORES DENTRO DEL SCRIPT EN EL SERVIDOR! ---

# Directorio local donde Proxmox GUARDA los archivos finales de respaldo VZDump.
# ¡Muy importante que esta ruta sea correcta, incluyendo /dump/ si Proxmox lo crea!
LOCAL_BACKUP_DIR="/RAID1/backups/dump/"

# Nombre del "remote" de rclone configurado para la cuenta de OneDrive en el servidor.
# Podría ser un remote directo (ej. onedrive_repositorio01) o un union (ej. pool_onedrive).
RCLONE_REMOTE_NAME="onedrive_repositorio01" # O "pool_onedrive" si se configuró

# Nombre de la carpeta PRINCIPAL DENTRO del remote de OneDrive donde se guardarán los respaldos.
# Rclone la creará si no existe. Si usas un union, esta carpeta estará dentro de la ruta definida para el upstream.
ONEDRIVE_DEST_FOLDER="Proxmox_Respaldos_Completos"

# Archivo donde se guardará el log de este script en el servidor Proxmox.
LOG_FILE="/var/log/rclone_proxmox_checklog_onedrive.log"

# Opciones comunes para los comandos de rclone (se pueden ajustar)
RCLONE_OPTS=(
    --log-file="${LOG_FILE}"
    --log-level NOTICE # Nivel NOTICE para ver archivos omitidos/saltados
    --stats 1m
    --stats-one-line
    --retries 3
    --retries-sleep 30s
    --low-level-retries 10
    --buffer-size 64M  # Ajusta según tu RAM disponible
    --checkers 8       # Ajusta según tu CPU
    --transfers 4      # Ajusta según tu ancho de banda de subida
    --ignore-existing
)

# --- Fin de la Configuración ---

# --- Función de Logging ---
DATE_FORMAT_LOG=$(date "+%Y-%m-%d %H:%M:%S")
log_message() {
    # Escribe el mensaje tanto en stdout/stderr (visible si se ejecuta manualmente)
    # como en el archivo de log si está definido.
    echo "${DATE_FORMAT_LOG} - $1" | tee -a "${LOG_FILE}"
}

# --- Inicio del Script ---
log_message "----------------------------------------------------"
log_message "Iniciando copia (con verificación de .log) a OneDrive (${RCLONE_REMOTE_NAME})"
log_message "Directorio de origen: ${LOCAL_BACKUP_DIR}"
log_message "Directorio de destino en OneDrive: ${RCLONE_REMOTE_NAME}:${ONEDRIVE_DEST_FOLDER}/"

# Verificar si el directorio local existe
if [ ! -d "${LOCAL_BACKUP_DIR}" ]; then
    log_message "ERROR CRÍTICO: El directorio local de respaldos ${LOCAL_BACKUP_DIR} no existe. Abortando."
    exit 1
fi

# Contador para errores de rclone
RCLONE_ERRORS=0

# Busca archivos de datos de respaldo (adapta las extensiones si usas otras)
# Usamos find para manejar nombres de archivo de forma segura
find "${LOCAL_BACKUP_DIR}" -maxdepth 1 -type f \( -name "vzdump-qemu-*.vma.gz" -o -name "vzdump-qemu-*.vma.zst" -o -name "vzdump-lxc-*.tar.gz" -o -name "vzdump-lxc-*.tar.zst" \) -print0 | while IFS= read -r -d $'\0' backup_data_file_path; do

    backup_data_file_name=$(basename "${backup_data_file_path}")

    # Construir nombre esperado del archivo .log y .notes
    # Elimina la extensión de datos conocida y añade .log o .notes
    base_name_part=$(echo "${backup_data_file_name}" | sed -E 's/\.vma\.gz$|\.vma\.zst$|\.tar\.gz$|\.tar\.zst$//')
    log_file_path="${LOCAL_BACKUP_DIR}${base_name_part}.log"
    log_file_name=$(basename "${log_file_path}")
    notes_file_path="${LOCAL_BACKUP_DIR}${base_name_part}.notes"
    notes_file_name=$(basename "${notes_file_path}")

    # Verificar si el archivo .log correspondiente existe
    if [ -f "${log_file_path}" ]; then
        # --- Archivo .log existe: Proceder a copiar ---
        log_message "Verificado (log existe): [${backup_data_file_name}]. Intentando copiar..."

        # Copiar archivo de datos
        /usr/bin/rclone copyto "${backup_data_file_path}" "${RCLONE_REMOTE_NAME}:${ONEDRIVE_DEST_FOLDER}/${backup_data_file_name}" "${RCLONE_OPTS[@]}"
        RCLONE_EXIT_CODE_DATA=$?
        if [ ${RCLONE_EXIT_CODE_DATA} -ne 0 ]; then
            RCLONE_ERRORS=$((RCLONE_ERRORS + 1))
            log_message "ERROR ${RCLONE_EXIT_CODE_DATA} al copiar ${backup_data_file_name}"
        else
            log_message "OK: ${backup_data_file_name} copiado/ignorado."

            # Si la copia del archivo de datos fue exitosa (o ignorada), copiar log y notes
            
            # Copiar archivo de log asociado
            log_message "Copiando log: ${log_file_name}"
            /usr/bin/rclone copyto "${log_file_path}" "${RCLONE_REMOTE_NAME}:${ONEDRIVE_DEST_FOLDER}/${log_file_name}" "${RCLONE_OPTS[@]}"
            if [ $? -ne 0 ]; then RCLONE_ERRORS=$((RCLONE_ERRORS + 1)); log_message "ERROR al copiar ${log_file_name}"; else log_message "OK: ${log_file_name} copiado/ignorado."; fi

            # Copiar archivo de notas si existe
            if [ -f "${notes_file_path}" ]; then
                 log_message "Copiando notes: ${notes_file_name}"
                 /usr/bin/rclone copyto "${notes_file_path}" "${RCLONE_REMOTE_NAME}:${ONEDRIVE_DEST_FOLDER}/${notes_file_name}" "${RCLONE_OPTS[@]}"
                 if [ $? -ne 0 ]; then RCLONE_ERRORS=$((RCLONE_ERRORS + 1)); log_message "ERROR al copiar ${notes_file_name}"; else log_message "OK: ${notes_file_name} copiado/ignorado."; fi
            fi
        fi
    else
        # --- Archivo .log NO existe: Omitir por ahora ---
        log_message "Omitiendo [${backup_data_file_name}] (archivo .log correspondiente [${log_file_name}] no encontrado aún)."
    fi
done

log_message "Fin del script de copia (con verificación de .log) a OneDrive. Errores de Rclone: ${RCLONE_ERRORS}"
log_message "----------------------------------------------------"

# Salir con 0 si no hubo errores de rclone, o con 1 si hubo algún error
if [ ${RCLONE_ERRORS} -gt 0 ]; then
    exit 1
else
    exit 0
fi 