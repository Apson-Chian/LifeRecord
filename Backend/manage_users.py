#!/usr/bin/env python3
"""Run on the server with the service environment; never share the owner's token."""
import argparse
import getpass
import server
import database

parser=argparse.ArgumentParser()
sub=parser.add_subparsers(dest='command',required=True)
create=sub.add_parser('create'); create.add_argument('label')
sub.add_parser('list')
revoke=sub.add_parser('revoke'); revoke.add_argument('user_id')
password=sub.add_parser('set-password'); password.add_argument('user_id'); password.add_argument('username')
args=parser.parse_args()
server.initialize()
with server.connect() as db:
    if args.command=='create':
        identifier,token=database.create_user(db,args.label)
        print('用户 ID：',identifier); print('独立同步密钥（仅显示一次）：',token)
    elif args.command=='list':
        for row in db.execute('SELECT id,label,disabled,created_at FROM users'):
            print(row['id'],row['label'],'disabled' if row['disabled'] else 'active')
    elif args.command=='set-password':
        if not db.execute('SELECT 1 FROM users WHERE id=? AND disabled=0',(args.user_id,)).fetchone():
            raise SystemExit('账号不存在或已停用')
        username=database.normalize_username(args.username)
        first=getpass.getpass('新密码（10–128 个字符）：')
        if first!=getpass.getpass('再次输入新密码：'): raise SystemExit('两次密码不一致')
        encoded=database.password_digest(first)
        if db.execute('SELECT 1 FROM account_credentials WHERE username=? AND user_id<>?',(username,args.user_id)).fetchone():
            raise SystemExit('账号名已被使用')
        db.execute('INSERT INTO account_credentials VALUES(?,?,?) ON CONFLICT(user_id) DO UPDATE SET username=excluded.username,password_hash=excluded.password_hash',(args.user_id,username,encoded))
        db.execute('DELETE FROM sessions WHERE user_id=?',(args.user_id,))
        print('账号密码已设置；旧登录会话已撤销，原同步密钥和记录保留。')
    else:
        db.execute('UPDATE users SET disabled=1 WHERE id=?',(args.user_id,))
        db.execute('DELETE FROM sessions WHERE user_id=?',(args.user_id,))
        print('访问已撤销；数据库内容保留供备份/恢复。')
