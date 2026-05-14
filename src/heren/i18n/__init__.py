"""
Heren MCP - Sistema de Internacionalización (i18n)

Soporta español (es) e inglés (en).
Detecta automáticamente el idioma del sistema.
Fallback a español si el idioma no está disponible.

Uso:
    from heren.i18n import get_text
    
    message = get_text("daemon_not_running")
    # o con idioma explícito:
    message = get_text("daemon_not_running", lang="en")
"""

import json
import locale
import logging
import os
from typing import Dict, Optional

logger = logging.getLogger(__name__)

# Idioma por defecto
DEFAULT_LANGUAGE = "es"

# Cache de traducciones
_translations_cache: Dict[str, Dict[str, str]] = {}


def _get_translations_dir() -> str:
    """Obtiene el directorio de archivos de traducción."""
    return os.path.dirname(os.path.abspath(__file__))


def _flatten_dict(d: dict, parent_key: str = "", sep: str = ".") -> dict:
    """Aplana un diccionario anidado."""
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(_flatten_dict(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)


def _load_translations(lang: str) -> Dict[str, str]:
    """Carga las traducciones para un idioma."""
    if lang in _translations_cache:
        return _translations_cache[lang]
    
    translations_dir = _get_translations_dir()
    file_path = os.path.join(translations_dir, f"{lang}.json")
    
    if not os.path.exists(file_path):
        logger.warning(f"Archivo de traducciones no encontrado: {file_path}")
        return {}
    
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        # Aplanar el diccionario anidado (ignorar __meta__)
        flat_translations = {}
        for category, messages in data.items():
            if category == "__meta__":
                continue
            if isinstance(messages, dict):
                for key, value in messages.items():
                    flat_translations[f"{category}.{key}"] = value
        _translations_cache[lang] = flat_translations
        return flat_translations
    except Exception as e:
        logger.error(f"Error cargando traducciones {lang}: {e}")
        return {}


def _detect_system_language() -> str:
    """
    Detecta el idioma del sistema operativo.
    
    Returns:
        Código de idioma ISO 639-1 (ej: 'es', 'en')
    """
    try:
        # Obtener locale del sistema
        system_locale = locale.getdefaultlocale()[0]
        if system_locale:
            lang_code = system_locale.split("_")[0].lower()
            if lang_code in ("es", "en"):
                return lang_code
    except Exception:
        pass
    
    # Fallback: intentar con environment variables
    for env_var in ["LANG", "LANGUAGE", "LC_ALL"]:
        env_lang = os.environ.get(env_var, "")
        if env_lang:
            lang_code = env_lang.split("_")[0].split(".")[0].lower()
            if lang_code in ("es", "en"):
                return lang_code
    
    # Default
    return DEFAULT_LANGUAGE


def get_text(key: str, lang: str = "", **kwargs) -> str:
    """
    Obtiene un mensaje traducido.
    
    Args:
        key: Clave del mensaje (ej: "daemon_not_running")
        lang: Código de idioma ("es" o "en"). Si está vacío, detecta automáticamente.
        **kwargs: Variables para interpolación en el mensaje
    
    Returns:
        Mensaje traducido
    
    Examples:
        >>> get_text("daemon_not_running")
        'GodotDaemon no está en ejecución. Inicia una sesión con use_daemon=True.'
        
        >>> get_text("operation_successful", operation="conectar señal")
        'Operación "conectar señal" completada exitosamente.'
        
        >>> get_text("daemon_not_running", lang="en")
        'GodotDaemon is not running. Start a session with use_daemon=True.'
    """
    # Usar idioma forzado si existe
    global _forced_language
    if _forced_language:
        lang = _forced_language
    
    # Detectar idioma si no se proporciona
    if not lang:
        lang = _detect_system_language()
    
    # Cargar traducciones
    translations = _load_translations(lang)
    
    # Fallback a español si no existe la clave
    if key not in translations and lang != DEFAULT_LANGUAGE:
        translations = _load_translations(DEFAULT_LANGUAGE)
    
    # Obtener mensaje
    message = translations.get(key, f"[{key}]")
    
    # Interpolación de variables
    if kwargs:
        try:
            message = message.format(**kwargs)
        except KeyError as e:
            logger.warning(f"Variable faltante en traducción '{key}': {e}")
    
    return message


def get_available_languages() -> list:
    """Lista los idiomas disponibles."""
    translations_dir = _get_translations_dir()
    languages = []
    
    for filename in os.listdir(translations_dir):
        if filename.endswith(".json"):
            lang_code = filename[:-5]  # Quitar .json
            languages.append(lang_code)
    
    return languages


def get_current_language() -> str:
    """Obtiene el idioma actual detectado."""
    return _detect_system_language()


def set_language(lang: str):
    """
    Fuerza un idioma específico para la sesión actual.
    
    Args:
        lang: Código de idioma ("es" o "en")
    """
    global _forced_language
    _forced_language = lang


# Variable para idioma forzado
_forced_language: Optional[str] = None


# Alias para compatibilidad
t = get_text
