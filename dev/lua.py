"""Mini banc de test Lua : charge lua51.dll (livré avec OBS, c'est LuaJIT = API Lua 5.1 comme WoW).

Usage :
  python -I lua.py check fichier1.lua fichier2.lua ...   -> vérifie la syntaxe (compilation)
  python -I lua.py run script.lua [arg ...]              -> exécute un script ; les arguments sont lus dans la table globale ARGS
"""
import ctypes
import os
import sys

DLL = r"C:\Program Files\obs-studio\bin\64bit\lua51.dll"
os.add_dll_directory(os.path.dirname(DLL))
lua = ctypes.CDLL(DLL)

VP = ctypes.c_void_p
lua.luaL_newstate.restype = VP
lua.luaL_openlibs.argtypes = [VP]
lua.luaL_loadbuffer.argtypes = [VP, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
lua.luaL_loadbuffer.restype = ctypes.c_int
lua.lua_pcall.argtypes = [VP, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_pcall.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [VP, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_settop.argtypes = [VP, ctypes.c_int]
lua.lua_createtable.argtypes = [VP, ctypes.c_int, ctypes.c_int]
lua.lua_pushstring.argtypes = [VP, ctypes.c_char_p]
lua.lua_rawseti.argtypes = [VP, ctypes.c_int, ctypes.c_int]
lua.lua_setfield.argtypes = [VP, ctypes.c_int, ctypes.c_char_p]
lua.lua_close.argtypes = [VP]

LUA_GLOBALSINDEX = -10002


def new_state():
    L = lua.luaL_newstate()
    lua.luaL_openlibs(L)
    return L


def error_text(L):
    msg = lua.lua_tolstring(L, -1, None)
    lua.lua_settop(L, -2)
    return msg.decode("utf-8", "replace") if msg else "(erreur inconnue)"


def load(L, path):
    with open(path, "rb") as f:
        data = f.read()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    name = ("@" + os.path.basename(path)).encode()
    return lua.luaL_loadbuffer(L, data, len(data), name)


def check(paths):
    bad = 0
    for path in paths:
        L = new_state()
        rc = load(L, path)
        if rc == 0:
            print("OK     " + os.path.basename(path))
        else:
            bad += 1
            print("ERREUR " + error_text(L))
        lua.lua_close(L)
    return 1 if bad else 0


def run(path, args):
    L = new_state()
    lua.lua_createtable(L, len(args), 0)
    for i, a in enumerate(args, 1):
        lua.lua_pushstring(L, a.encode())
        lua.lua_rawseti(L, -2, i)
    lua.lua_setfield(L, LUA_GLOBALSINDEX, b"ARGS")
    if load(L, path) != 0:
        print("ERREUR de syntaxe : " + error_text(L))
        return 1
    if lua.lua_pcall(L, 0, 0, 0) != 0:
        print("ERREUR d'exécution : " + error_text(L))
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "run"):
        print(__doc__)
        sys.exit(2)
    code = check(sys.argv[2:]) if sys.argv[1] == "check" else run(sys.argv[2], sys.argv[3:])
    sys.stdout.flush()
    sys.exit(code)
