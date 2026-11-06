import { DeviceInfo, FileDto, PrepareUploadResult, TokenEntry } from '../common/Models';

/**
 * Encoder/decoder for the JSON dictionaries used by LocalSend Protocol v2.2.
 *
 * ArkTS (strict static typing) does not allow index signatures, dynamic
 * property assignment or `obj[key]` access, so the `files` object cannot be
 * modelled as an interface. This helper does minimal, structure-aware JSON
 * scanning and exposes plain arrays to the rest of the app.
 */
interface JsonMember {
  key: string;
  value: string;
}

function isWs(c: string): boolean {
  return c === ' ' || c === '\n' || c === '\r' || c === '\t';
}

function stringEnd(text: string, start: number): number {
  let i: number = start + 1;
  let escaped: boolean = false;
  while (i < text.length) {
    let c: string = text[i];
    if (escaped) {
      escaped = false;
    } else if (c === '\\') {
      escaped = true;
    } else if (c === '"') {
      return i + 1;
    }
    i++;
  }
  return text.length;
}

function balancedEnd(text: string, start: number): number {
  let depth: number = 0;
  let inString: boolean = false;
  let escaped: boolean = false;
  for (let i = start; i < text.length; i++) {
    let c: string = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c === '\\') {
        escaped = true;
      } else if (c === '"') {
        inString = false;
      }
    } else if (c === '"') {
      inString = true;
    } else if (c === '{' || c === '[') {
      depth++;
    } else if (c === '}' || c === ']') {
      depth--;
      if (depth === 0) {
        return i + 1;
      }
    }
  }
  return text.length;
}

function valueEnd(text: string, start: number): number {
  let i: number = start;
  while (i < text.length && isWs(text[i])) {
    i++;
  }
  if (i >= text.length) {
    return i;
  }
  if (text[i] === '"') {
    return stringEnd(text, i);
  }
  if (text[i] === '{' || text[i] === '[') {
    return balancedEnd(text, i);
  }
  let j: number = i;
  while (j < text.length && text[j] !== ',' && text[j] !== '}' && text[j] !== ']' && !isWs(text[j])) {
    j++;
  }
  return j;
}

/** Returns the raw JSON value of a named top-level member, or an empty string. */
function memberRaw(text: string, member: string): string {
  let key: string = '"' + member + '"';
  let at: number = text.indexOf(key);
  while (at >= 0) {
    let k: number = at + key.length;
    while (k < text.length && isWs(text[k])) {
      k++;
    }
    if (k < text.length && text[k] === ':') {
      let start: number = k + 1;
      while (start < text.length && isWs(text[start])) {
        start++;
      }
      return text.substring(start, valueEnd(text, start));
    }
    at = text.indexOf(key, at + key.length);
  }
  return '';
}

function splitObject(raw: string): JsonMember[] {
  let list: JsonMember[] = [];
  if (raw.length < 2 || raw[0] !== '{') {
    return list;
  }
  let i: number = 1;
  while (i < raw.length - 1) {
    while (i < raw.length && (isWs(raw[i]) || raw[i] === ',')) {
      i++;
    }
    if (i >= raw.length - 1 || raw[i] !== '"') {
      break;
    }
    let keyEnd: number = stringEnd(raw, i);
    let key: string = JSON.parse(raw.substring(i, keyEnd)) as string;
    i = keyEnd;
    while (i < raw.length && (isWs(raw[i]) || raw[i] === ':')) {
      i++;
    }
    let end: number = valueEnd(raw, i);
    let item: JsonMember = { key: key, value: raw.substring(i, end) };
    list.push(item);
    i = end;
  }
  return list;
}

export class ProtocolJson {
  static parseInfo(body: string): DeviceInfo | null {
    let raw: string = memberRaw(body, 'info');
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as DeviceInfo;
    } catch (e) {
      return null;
    }
  }

  static parseFileList(body: string): FileDto[] {
    let list: FileDto[] = [];
    let members: JsonMember[] = splitObject(memberRaw(body, 'files'));
    for (let i = 0; i < members.length; i++) {
      try {
        let dto = JSON.parse(members[i].value) as FileDto;
        if (dto.id === undefined || dto.id.length === 0) {
          dto.id = members[i].key;
        }
        list.push(dto);
      } catch (e) {
        // Skip malformed entries; the sender will get a 400 if nothing remains.
      }
    }
    return list;
  }

  static buildPrepareUploadBody(self: DeviceInfo, files: FileDto[]): string {
    let parts: string = '';
    for (let i = 0; i < files.length; i++) {
      parts += (i > 0 ? ',' : '') + JSON.stringify(files[i].id) + ':' + JSON.stringify(files[i]);
    }
    return '{"info":' + JSON.stringify(self) + ',"files":{' + parts + '}}';
  }

  static parsePrepareUploadResult(body: string): PrepareUploadResult {
    let rawId: string = memberRaw(body, 'sessionId');
    let sessionId: string = '';
    if (rawId.length > 0) {
      try {
        sessionId = JSON.parse(rawId) as string;
      } catch (e) {
        sessionId = '';
      }
    }
    let tokens: TokenEntry[] = [];
    let members: JsonMember[] = splitObject(memberRaw(body, 'files'));
    for (let i = 0; i < members.length; i++) {
      try {
        let token: string = JSON.parse(members[i].value) as string;
        let entry: TokenEntry = { id: members[i].key, token: token };
        tokens.push(entry);
      } catch (e) {
        // Ignore entries without a usable token.
      }
    }
    let result: PrepareUploadResult = { sessionId: sessionId, tokens: tokens };
    return result;
  }

  static buildPrepareUploadResponse(sessionId: string, tokens: TokenEntry[]): string {
    let parts: string = '';
    for (let i = 0; i < tokens.length; i++) {
      parts += (i > 0 ? ',' : '') + JSON.stringify(tokens[i].id) + ':' + JSON.stringify(tokens[i].token);
    }
    return '{"sessionId":' + JSON.stringify(sessionId) + ',"files":{' + parts + '}}';
  }

  static buildPrepareDownloadResponse(info: DeviceInfo, sessionId: string, files: FileDto[]): string {
    let parts: string = '';
    for (let i = 0; i < files.length; i++) {
      parts += (i > 0 ? ',' : '') + JSON.stringify(files[i].id) + ':' + JSON.stringify(files[i]);
    }
    return '{"info":' + JSON.stringify(info) + ',"sessionId":' + JSON.stringify(sessionId) +
      ',"files":{' + parts + '}}';
  }
}
