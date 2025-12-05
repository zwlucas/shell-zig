# Shell em Zig

Um shell simples implementado em Zig que suporta comandos builtin e execução de programas externos.

## Estrutura do Projeto

```
src/
├── main.zig        # Ponto de entrada e loop REPL
├── parser.zig      # Parsing de comandos e argumentos
├── builtins.zig    # Implementação de comandos builtin
├── path.zig        # Busca de executáveis no PATH
├── executor.zig    # Execução de programas externos
└── shell.zig       # Orquestração de comandos
```

## Módulos

### main.zig
- Ponto de entrada da aplicação
- Implementa o REPL (Read-Eval-Print Loop)
- Gerencia entrada/saída do shell

### parser.zig
- `parseCommand()`: Separa nome do comando dos argumentos
- `parseArgs()`: Converte string de argumentos em array

### builtins.zig
- `isBuiltin()`: Verifica se comando é builtin
- `executeExit()`: Implementa comando `exit`
- `executeEcho()`: Implementa comando `echo`
- `executeType()`: Implementa comando `type`

### path.zig
- `findInPath()`: Busca executáveis no PATH do sistema
- Verifica permissões de execução

### executor.zig
- `runExternalProgram()`: Executa programas externos
- Gerencia processos filhos

### shell.zig
- `executeCommand()`: Orquestra execução de comandos
- Decide entre builtin ou programa externo

## Comandos Suportados

### Builtins
- `exit` - Encerra o shell
- `echo [args]` - Imprime argumentos
- `type <command>` - Mostra tipo/localização do comando

### Programas Externos
Qualquer executável encontrado no PATH pode ser executado.

## Compilar e Executar

```bash
# Compilar
zig build

# Executar
./zig-out/bin/main
```

## Como Adicionar Novos Builtins

1. Adicione o nome à lista `BUILTINS` em `builtins.zig`
2. Implemente a função `executeNomeDoComando()` em `builtins.zig`
3. Adicione o case no `executeCommand()` em `shell.zig`
