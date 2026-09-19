//! 回环 HTTP/1.1 客户端：只够和本机的 Sidecar 说话。
//!
//! 为什么手写而不是引入 HTTP 客户端库：这条链路上**只有我们自己写的一台服务器**，
//! 协议面被刻意压到最小 —— 请求永远 `Connection: close`、响应永远以连接关闭表示结束
//! （见 Python 侧 `server.py`），因此不需要处理连接复用、chunked 编码、重定向、
//! TLS、代理与 cookie。为了这点需求引入一个带 TLS 栈的客户端库，会把依赖树和攻击面
//! 都放大一圈，而它解决的问题这里一个都不存在。
//!
//! 代价是：**这个客户端不能拿去做别的用途**。一旦要访问真正的远程服务（有 TLS、
//! 有重定向、有压缩），应当换成成熟客户端库，而不是在这里继续加分支。

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, SocketAddr, TcpStream};
use std::time::Duration;

use serde_json::Value;

/// 建连超时：连本机端口不该用到这么久，超时说明进程状态异常。
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);

/// 读超时。必须**长于** Sidecar 自己对上游的超时（Python 侧 `DEFAULT_TIMEOUT_SECONDS = 60`），
/// 否则模型服务慢的时候，我们会先超时断开，用户看到的是"连接中断"，
/// 而不是 Sidecar 已经准备好的那条"上游超时"错误信封。
const READ_TIMEOUT: Duration = Duration::from_secs(90);

/// 单次响应头部大小上限。防御性的：解析失败也不该无限吃内存。
const MAX_HEADER_BYTES: usize = 32 * 1024;

#[derive(Debug, Clone)]
pub struct HttpError {
    pub message: String,
}

impl HttpError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

/// 允许的方法。刻意用枚举而不是 `&str`：这样调用方无法把任意内容拼进请求行。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Method {
    Get,
    Post,
}

impl Method {
    fn as_str(self) -> &'static str {
        match self {
            Method::Get => "GET",
            Method::Post => "POST",
        }
    }
}

/// 指向某个 Sidecar 实例的客户端。`token` 只在此对象的内存里。
pub struct LoopbackClient {
    port: u16,
    token: String,
}

impl LoopbackClient {
    pub fn new(port: u16, token: impl Into<String>) -> Self {
        Self {
            port,
            token: token.into(),
        }
    }

    /// 发一个请求并返回尚未读完的响应。
    pub fn send(&self, method: Method, path: &str, body: Option<&Value>) -> Result<Response, HttpError> {
        // 路径由本仓库的常量提供，仍然挡一次：CRLF 注入请求行的代价太低，防御成本也低。
        if path.contains(['\r', '\n']) {
            return Err(HttpError::new("请求路径包含非法字符"));
        }

        let payload = match body {
            Some(value) => Some(
                serde_json::to_vec(value)
                    .map_err(|e| HttpError::new(format!("请求体无法序列化：{e}")))?,
            ),
            None => None,
        };

        let address = SocketAddr::from((Ipv4Addr::LOCALHOST, self.port));
        let stream = TcpStream::connect_timeout(&address, CONNECT_TIMEOUT)
            .map_err(|e| HttpError::new(format!("无法连接到 Sidecar（127.0.0.1:{}）：{e}", self.port)))?;
        stream
            .set_read_timeout(Some(READ_TIMEOUT))
            .map_err(|e| HttpError::new(format!("无法设置读超时：{e}")))?;
        stream
            .set_write_timeout(Some(CONNECT_TIMEOUT))
            .map_err(|e| HttpError::new(format!("无法设置写超时：{e}")))?;

        // 注意：这个字符串里含 token。它只在内存中短暂存在，
        // 绝不能被打印、写日志或塞进任何错误信息。
        let mut head = format!(
            "{} {} HTTP/1.1\r\nHost: 127.0.0.1:{}\r\nAuthorization: Bearer {}\r\nConnection: close\r\n",
            method.as_str(),
            path,
            self.port,
            self.token,
        );
        if let Some(payload) = &payload {
            head.push_str("Content-Type: application/json\r\n");
            head.push_str(&format!("Content-Length: {}\r\n", payload.len()));
        }
        head.push_str("\r\n");

        let mut stream = stream;
        stream
            .write_all(head.as_bytes())
            .and_then(|()| match &payload {
                Some(payload) => stream.write_all(payload),
                None => Ok(()),
            })
            .and_then(|()| stream.flush())
            .map_err(|e| HttpError::new(format!("请求发送失败：{e}")))?;

        let mut reader = BufReader::new(stream);
        let status = read_status_line(&mut reader)?;
        drain_headers(&mut reader)?;
        Ok(Response { status, reader })
    }
}

fn read_status_line(reader: &mut BufReader<TcpStream>) -> Result<u16, HttpError> {
    let mut line = String::new();
    let read = reader
        .read_line(&mut line)
        .map_err(|e| HttpError::new(format!("读取响应状态行失败：{e}")))?;
    if read == 0 {
        return Err(HttpError::new("Sidecar 没有返回任何响应（连接被直接关闭）"));
    }

    // 形如 "HTTP/1.1 200 OK"。只取中间的三个数字。
    let mut parts = line.split_whitespace();
    let _version = parts.next();
    let code = parts
        .next()
        .and_then(|token| token.parse::<u16>().ok())
        .ok_or_else(|| HttpError::new("响应状态行无法解析"))?;
    Ok(code)
}

fn drain_headers(reader: &mut BufReader<TcpStream>) -> Result<(), HttpError> {
    let mut consumed = 0usize;
    loop {
        let mut line = String::new();
        let read = reader
            .read_line(&mut line)
            .map_err(|e| HttpError::new(format!("读取响应头失败：{e}")))?;
        if read == 0 {
            // 头部没结束就断了。交给调用方按"没有正文"处理不合适 —— 明说更好。
            return Err(HttpError::new("响应头不完整（连接提前结束）"));
        }
        consumed += read;
        if consumed > MAX_HEADER_BYTES {
            return Err(HttpError::new("响应头超出上限"));
        }
        if line == "\r\n" || line == "\n" {
            return Ok(());
        }
    }
}

/// 响应。正文按需读取 —— 流式端点要一行一行地取，一次性端点则整段读。
pub struct Response {
    pub status: u16,
    reader: BufReader<TcpStream>,
}

impl Response {
    /// 读到连接关闭为止。用于非流式响应（我们的服务器总是发 Content-Length + close）。
    pub fn read_body(&mut self) -> Result<String, HttpError> {
        let mut text = String::new();
        self.reader
            .read_to_string(&mut text)
            .map_err(|e| HttpError::new(format!("读取响应正文失败：{e}")))?;
        Ok(text)
    }

    /// 读一行（不含行尾）。`Ok(None)` 表示对端已关闭。
    pub fn next_line(&mut self) -> Result<Option<String>, HttpError> {
        let mut line = String::new();
        let read = self
            .reader
            .read_line(&mut line)
            .map_err(|e| HttpError::new(format!("读取响应流失败：{e}")))?;
        if read == 0 {
            return Ok(None);
        }
        Ok(Some(line.trim_end_matches(['\r', '\n']).to_string()))
    }

    /// 解析正文 JSON。正文为空或不是 JSON 都是明确错误，不返回 `Value::Null` 糊过去。
    pub fn read_json(&mut self) -> Result<Value, HttpError> {
        let text = self.read_body()?;
        serde_json::from_str(&text).map_err(|e| HttpError::new(format!("响应不是合法 JSON：{e}")))
    }
}
