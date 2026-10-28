# Como Testar a Conexão com o Informix (Java, Spring Boot e Node.js)

Este guia documenta o processo completo para conectar sua máquina de desenvolvimento local ao servidor IBM Informix rodando em uma VM remota (ex.: IBM Cloud / TechZone) e executar testes automatizados com **Java Puro (JDBC)**, **Spring Boot** e **Node.js**.

---

## 1. Arquitetura de Comunicação e Portas

O IBM Informix utiliza protocolos de comunicação diferentes para clientes baseados em **JDBC** e clientes baseados em **CLI/ODBC (Node.js)**:

| Stack / Cliente                | Protocolo                     | Instância Informix   | Porta Padrão da VM | Descrição                                                  |
| :----------------------------- | :---------------------------- | :-------------------- | :------------------ | :----------------------------------------------------------- |
| **Java Puro (JDBC)**     | **SQLI** (nativo)       | `ol_informix1410` | `32615/tcp`       | Usa o driver JDBC oficial (`com.informix.jdbc.IfxDriver`). |
| **Spring Boot**          | **SQLI** (nativo)       | `ol_informix1410` | `32615/tcp`       | Usa pool HikariCP +`com.informix.jdbc.IfxDriver`.          |
| **Node.js (`ibm_db`)** | **DRDA** (Db2/Informix) | `dr_informix1410` | `30902/tcp`       | Driver binário CLI/ODBC mantido pela IBM.                   |

---

## 2. Pré-requisitos e Dados da VM

- **Chave SSH:** `./privatekey/vm_ssh_key.vm`
- **IP Público da VM:** `169.44.161.21` (exemplo TechZone)
- **Porta SSH Externa:** `32399` (ou `22` em outros ambientes)
- **Usuário SSH:** `itzuser`
- **Usuário do Banco:** `informix`

---

## 3. Executar os Testes

Na pasta raiz do projeto, execute o script de automação [`test-connection.sh`](test-connection.sh:1). Ele detecta e instala dependências faltantes (via Homebrew no macOS ou dnf/apt no Linux) e roda os testes.

#### Opção A: Teste com Spring Boot (Recomendado para Java)

```bash
./test-connection.sh spring
```

*(Cria o projeto Spring Boot com HikariCP, instala o driver no repositório local do Maven e consulta os clientes do banco `stores`)*.

#### Opção B: Teste com Node.js

```bash
./test-connection.sh node
```

*(Cria o mini-projeto Node.js com `ibm_db`, conecta via DRDA na porta `30902` e exibe os registros em tabela)*.

#### Opção C: Teste com Java Puro (JDBC)

```bash
./test-connection.sh java
```

*(Baixa automaticamente o `ifxjdbc.jar` do Maven Central, compila e executa via `javac`/`java`)*.

#### Opção D: Executar Todos os Testes

```bash
./test-connection.sh all
```

---

## 4. Configurações de Código para os Projetos do Cliente

### A. Spring Boot (Java)

#### `pom.xml`

```xml
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-jdbc</artifactId>
    </dependency>

    <!-- Driver Oficial JDBC do Informix -->
    <dependency>
        <groupId>com.ibm.informix</groupId>
        <artifactId>jdbc</artifactId>
        <version>4.50.12</version>
    </dependency>
</dependencies>
```

#### `application.properties`

```properties
spring.datasource.url=jdbc:informix-sqli://127.0.0.1:32615/stores:INFORMIXSERVER=ol_informix1410
spring.datasource.username=informix
spring.datasource.password=${IFX_PASS}
spring.datasource.driver-class-name=com.informix.jdbc.IfxDriver
```

---

### B. Node.js

#### `package.json`

```json
{
  "name": "informix-node-client",
  "version": "1.0.0",
  "dependencies": {
    "ibm_db": "^3.2.0"
  }
}
```

#### `index.js`

```javascript
const ibmdb = require('ibm_db');

const connStr = "DATABASE=stores;HOSTNAME=127.0.0.1;PORT=30902;PROTOCOL=TCPIP;UID=informix;PWD=" + process.env.IFX_PASS + ";SERVER=dr_informix1410;";

ibmdb.open(connStr, (err, conn) => {
  if (err) {
    console.error("Erro na conexao:", err.message);
    return;
  }
  console.log("Conectado via DRDA!");
  conn.query("SELECT FIRST 5 customer_num, fname, lname FROM customer", (err, data) => {
    if (err) console.error(err);
    else console.table(data);
    conn.close();
  });
});
```

---

### C. DBeaver / Interface Gráfica

- **Driver:** IBM Informix
- **Host:** `169.44.161.21`
- **Port:** `32615`
- **Database:** `stores`
- **Server Name:** `ol_informix1410`
- **Username:** `informix`
- **Password:** `<senha>`
