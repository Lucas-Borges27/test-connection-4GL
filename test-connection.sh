#!/usr/bin/env bash
###############################################################################
# test-connection.sh
#
# Script de automação e teste de conexão com o banco IBM Informix.
# Suporta:
#   1. Java Puro (via JDBC standalone)
#   2. Spring Boot (Maven)
#   3. Node.js (via ibm_db)
#
# USO:
#   ./test-connection.sh java        # Testa via Java Puro / JDBC
#   ./test-connection.sh spring      # Testa via Spring Boot (Maven)
#   ./test-connection.sh node        # Testa via Node.js
#   ./test-connection.sh all         # Roda todos os testes disponíveis
#   ./test-connection.sh download-jdbc # Apenas baixa o ifxjdbc.jar
###############################################################################

set -euo pipefail

# ---------- Configurações e Variáveis ----------
IFX_HOST="${IFX_HOST:-169.44.161.21}"
IFX_PORT="${IFX_PORT:-32615}"
IFX_DRDA_PORT="${IFX_DRDA_PORT:-30902}"
IFX_DB="${IFX_DB:-stores}"
IFX_SERVER="${IFX_SERVER:-ol_informix1410}"
IFX_DRDA_SERVER="${IFX_DRDA_SERVER:-dr_informix1410}"
IFX_USER="${IFX_USER:-informix}"
JDBC_VERSION="${JDBC_VERSION:-4.50.12}"
JDBC_JAR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ifxjdbc.jar"
# Exporta para que o Java/Node/Spring enxerguem os valores (sem isso caem nos defaults internos)
export IFX_HOST IFX_PORT IFX_DRDA_PORT IFX_DB IFX_SERVER IFX_DRDA_SERVER IFX_USER

c_info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
c_ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
c_warn() { echo -e "\033[1;33m[AVISO]\033[0m $*"; }
c_err()  { echo -e "\033[1;31m[ERRO]\033[0m $*" >&2; }

check_credentials() {
  if [ -z "${IFX_PASS:-}" ]; then
    read -rsp "Digite a senha do usuário Informix ($IFX_USER): " IFX_PASS
    echo
    export IFX_PASS
  fi
}

# =============================================================================
# Helper de auto-instalação de dependências do sistema (macOS / Linux)
# =============================================================================
ensure_installed() {
  local tool="$1"
  local pkg_mac="$2"
  local pkg_linux="$3"

  if command -v "$tool" &>/dev/null; then
    return 0
  fi

  c_warn "Ferramenta '$tool' não encontrada. Tentando instalar automaticamente..."

  local os_type
  os_type="$(uname -s)"

  if [ "$os_type" = "Darwin" ]; then
    if command -v brew &>/dev/null; then
      c_info "Instalando $pkg_mac via Homebrew..."
      brew install "$pkg_mac"
    else
      c_err "Homebrew ('brew') não encontrado. Instale o pacote '$pkg_mac' manualmente."
      return 1
    fi
  elif [ "$os_type" = "Linux" ]; then
    if command -v dnf &>/dev/null; then
      sudo dnf install -y "$pkg_linux"
    elif command -v apt-get &>/dev/null; then
      sudo apt-get update && sudo apt-get install -y "$pkg_linux"
    else
      c_err "Gerenciador de pacotes não suportado. Instale '$pkg_linux' manualmente."
      return 1
    fi
  else
    c_err "Sistema operacional não suportado: $os_type"
    return 1
  fi

  if command -v "$tool" &>/dev/null; then
    c_ok "Ferramenta '$tool' instalada com sucesso."
    return 0
  else
    c_err "Falha ao instalar '$tool'."
    return 1
  fi
}

# Garante que java/javac/mvn usem o JDK 25 (LTS), mesmo que outro esteja no PATH
use_java25() {
  local home=""
  if [ "$(uname -s)" = "Darwin" ]; then
    # Atenção: 'java_home -v 25' devolve qualquer JDK >= 25 (ex.: 27), então confere a versão exata
    if command -v brew &>/dev/null; then
      local brew_jdk
      brew_jdk="$(brew --prefix openjdk@25 2>/dev/null)/libexec/openjdk.jdk/Contents/Home"
      [ -x "$brew_jdk/bin/java" ] && home="$brew_jdk"
    fi
    if [ -z "$home" ]; then
      local cand
      cand="$(/usr/libexec/java_home -v 25 2>/dev/null || true)"
      if [ -n "$cand" ] && "$cand/bin/java" -version 2>&1 | head -1 | grep -q '"25'; then
        home="$cand"
      fi
    fi
  fi
  if [ -n "$home" ]; then
    export JAVA_HOME="$home"
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
  c_info "Java em uso: $(java -version 2>&1 | head -1)"
}

# =============================================================================
# Download do JAR JDBC (Maven Central)
# =============================================================================
download_jdbc() {
  if [ -f "$JDBC_JAR" ]; then
    c_info "Driver JDBC local ($JDBC_JAR) já existe."
  else
    c_info "Baixando Informix JDBC driver v${JDBC_VERSION} do Maven Central..."
    curl -fsSL -o "$JDBC_JAR" \
      "https://repo1.maven.org/maven2/com/ibm/informix/jdbc/${JDBC_VERSION}/jdbc-${JDBC_VERSION}.jar"
    c_ok "Download concluído: $JDBC_JAR"
  fi
}

# =============================================================================
# Teste 1: Java Puro (JDBC standalone)
# =============================================================================
test_java() {
  c_info "=== Executando Teste: Java Puro (JDBC) ==="
  check_credentials
  download_jdbc

  if ! ensure_installed "java" "openjdk@25" "java-25-openjdk-devel"; then return 1; fi
  if ! ensure_installed "javac" "openjdk@25" "java-25-openjdk-devel"; then return 1; fi
  use_java25

  cat > TestIfxConnection.java << 'EOF'
import java.sql.*;

public class TestIfxConnection {
    public static void main(String[] args) throws Exception {
        String host = System.getenv().getOrDefault("IFX_HOST", "localhost");
        String port = System.getenv().getOrDefault("IFX_PORT", "29233");
        String db = System.getenv().getOrDefault("IFX_DB", "stores");
        String server = System.getenv().getOrDefault("IFX_SERVER", "ol_informix1410_5");
        String user = System.getenv().getOrDefault("IFX_USER", "informix");
        String pass = System.getenv("IFX_PASS");

        Class.forName("com.informix.jdbc.IfxDriver");
        String url = String.format("jdbc:informix-sqli://%s:%s/%s:INFORMIXSERVER=%s", host, port, db, server);
        System.out.println("Conectando em: " + url + " com usuário " + user);

        try (Connection conn = DriverManager.getConnection(url, user, pass);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT FIRST 5 customer_num, fname, lname FROM customer")) {
            System.out.println("--- Conexão JDBC estabelecida com sucesso! ---");
            while (rs.next()) {
                System.out.printf("Cliente ID: %d | Nome: %s %s%n", rs.getInt(1), rs.getString(2).trim(), rs.getString(3).trim());
            }
            System.out.println("----------------------------------------------");
        } catch (Exception e) {
            System.err.println("Falha na conexão JDBC: " + e);
            e.printStackTrace();
            System.exit(1);
        }
    }
}
EOF

  c_info "Compilando e executando teste Java..."
  javac -cp "$JDBC_JAR" TestIfxConnection.java
  java -cp ".:$JDBC_JAR" TestIfxConnection
  rm -f TestIfxConnection.java TestIfxConnection.class
  c_ok "Teste Java JDBC concluído com sucesso."
}

# =============================================================================
# Teste 2: Spring Boot
# =============================================================================
test_spring() {
  c_info "=== Executando Teste: Spring Boot ==="
  check_credentials
  download_jdbc

  if ! ensure_installed "mvn" "maven" "maven"; then return 1; fi
  if ! ensure_installed "java" "openjdk@25" "java-25-openjdk-devel"; then return 1; fi
  use_java25

  # Instala o JAR no repositório local Maven (.m2) para garantir que esteja acessível
  c_info "Garantindo driver Informix no repositório local Maven..."
  mvn install:install-file \
    -Dfile="$JDBC_JAR" \
    -DgroupId="com.ibm.informix" \
    -DartifactId="jdbc" \
    -Dversion="${JDBC_VERSION}" \
    -Dpackaging="jar" \
    -DgeneratePom=true \
    -q

  local spring_dir="test-spring-boot"
  mkdir -p "$spring_dir/src/main/java/com/example/demo" "$spring_dir/src/main/resources"

  cat > "$spring_dir/pom.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.5.7</version>
        <relativePath/>
    </parent>
    <groupId>com.example</groupId>
    <artifactId>demo-informix</artifactId>
    <version>0.0.1-SNAPSHOT</version>

    <properties>
        <java.version>25</java.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-jdbc</artifactId>
        </dependency>
        <dependency>
            <groupId>com.ibm.informix</groupId>
            <artifactId>jdbc</artifactId>
            <version>${JDBC_VERSION}</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
EOF

  cat > "$spring_dir/src/main/resources/application.properties" << EOF
spring.datasource.url=jdbc:informix-sqli://\${IFX_HOST:$IFX_HOST}:\${IFX_PORT:$IFX_PORT}/\${IFX_DB:$IFX_DB}:INFORMIXSERVER=\${IFX_SERVER:$IFX_SERVER}
spring.datasource.username=\${IFX_USER:$IFX_USER}
spring.datasource.password=\${IFX_PASS}
spring.datasource.driver-class-name=com.informix.jdbc.IfxDriver
# O driver 3.70 (JDBC 3.0) não implementa Connection.isValid(); o Hikari valida por query
spring.datasource.hikari.connection-test-query=SELECT 1 FROM systables WHERE tabid = 1
EOF

  cat > "$spring_dir/src/main/java/com/example/demo/DemoApplication.java" << 'EOF'
package com.example.demo;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.jdbc.core.JdbcTemplate;

@SpringBootApplication
public class DemoApplication implements CommandLineRunner {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }

    @Override
    public void run(String... args) {
        System.out.println("\n--- [Spring Boot] Executando query via JdbcTemplate ---");
        jdbcTemplate.query("SELECT FIRST 5 customer_num, fname, lname FROM customer", (rs) -> {
            System.out.printf("Cliente ID: %d | Nome: %s %s%n",
                    rs.getInt("customer_num"),
                    rs.getString("fname").trim(),
                    rs.getString("lname").trim());
        });
        System.out.println("--- [Spring Boot] Consulta executada com sucesso! ---\n");
    }
}
EOF

  c_info "Executando Spring Boot..."
  (cd "$spring_dir" && mvn spring-boot:run -Dspring-boot.run.arguments="--server.port=0")
  c_ok "Teste Spring Boot concluído com sucesso."
}

# =============================================================================
# Teste 3: Node.js (ibm_db)
# =============================================================================
test_node() {
  c_info "=== Executando Teste: Node.js ==="
  check_credentials

  if ! ensure_installed "node" "node" "nodejs"; then return 1; fi
  if ! ensure_installed "npm" "node" "npm"; then return 1; fi

  # Garante que o Node.js use o host e porta DRDA corretos
  export IFX_HOST="${IFX_HOST:-127.0.0.1}"
  export IFX_DRDA_PORT="${IFX_DRDA_PORT:-30902}"
  export IFX_DRDA_SERVER="${IFX_DRDA_SERVER:-dr_informix1410}"

  local node_dir="test-node"
  mkdir -p "$node_dir"

  cat > "$node_dir/package.json" << 'EOF'
{
  "name": "informix-node-test",
  "version": "1.0.0",
  "description": "Teste de conexao Informix via Node.js",
  "main": "test.js",
  "dependencies": {
    "ibm_db": "^3.2.0"
  }
}
EOF

  cat > "$node_dir/test.js" << 'EOF'
const ibmdb = require('ibm_db');

const host = process.env.IFX_HOST || '127.0.0.1';
const port = process.env.IFX_DRDA_PORT || process.env.IFX_PORT || '30902';
const db = process.env.IFX_DB || 'stores';
const server = process.env.IFX_DRDA_SERVER || 'dr_informix1410';
const user = process.env.IFX_USER || 'informix';
const password = process.env.IFX_PASS;

if (!password) {
  console.error("ERRO: Variavel IFX_PASS nao definida.");
  process.exit(1);
}

const connStr = `DATABASE=${db};HOSTNAME=${host};PORT=${port};PROTOCOL=TCPIP;UID=${user};PWD=${password};SERVER=${server};`;
console.log(`Conectando Node.js (DRDA) em ${host}:${port}/${db} (Server: ${server})...`);

ibmdb.open(connStr, (err, conn) => {
  if (err) {
    console.error("Falha ao conectar via Node.js:", err.message);
    process.exit(1);
  }

  console.log("--- Conexao Node.js estabelecida com sucesso! ---");
  conn.query("SELECT FIRST 5 customer_num, fname, lname FROM customer", (err, data) => {
    if (err) {
      console.error("Erro na consulta:", err.message);
    } else {
      console.table(data);
    }

    conn.close(() => {
      console.log("Conexao Node.js encerrada.");
    });
  });
});
EOF

  c_info "Instalando dependencias npm (se necessario)..."
  (cd "$node_dir" && [ ! -d "node_modules" ] && npm install || true)

  c_info "Rodando script Node.js..."
  (cd "$node_dir" && node test.js)
  c_ok "Teste Node.js concluído com sucesso."
}

# =============================================================================
# Menu Principal
# =============================================================================
main() {
  local target="${1:-}"

  case "$target" in
    download-jdbc)
      download_jdbc
      ;;
    java)
      test_java
      ;;
    spring)
      test_spring
      ;;
    node)
      test_node
      ;;
    all)
      test_java
      echo
      test_spring
      echo
      test_node
      ;;
    *)
      echo "=========================================================="
      echo "  Testador de Conexão Informix (Java, Spring Boot, Node)  "
      echo "=========================================================="
      echo "Uso: $0 [opcao]"
      echo ""
      echo "Opções disponíveis:"
      echo "  java           Testa via Java puro usando JDBC local"
      echo "  spring         Testa via aplicação Spring Boot (Maven)"
      echo "  node           Testa via Node.js (driver ibm_db)"
      echo "  all            Executa todos os testes"
      echo "  download-jdbc  Apenas baixa o ifxjdbc.jar"
      echo ""
      echo "Variáveis de ambiente suportadas:"
      echo "  IFX_HOST   (padrão: localhost)"
      echo "  IFX_PORT   (padrão: 29233)"
      echo "  IFX_DB     (padrão: stores)"
      echo "  IFX_SERVER (padrão: ol_informix1410_5)"
      echo "  IFX_USER   (padrão: informix)"
      echo "  IFX_PASS   (se não informada, o script pergunta)"
      exit 1
      ;;
  esac
}

main "$@"
