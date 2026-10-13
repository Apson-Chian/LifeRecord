#!/usr/bin/env python3
"""Run on the server with the service environment; never share the owner's token."""
import argparse
import server
import database

parser=argparse.ArgumentParser()
sub=parser.add_subparsers(dest='command',required=True)
create=sub.add_parser('create'); create.add_argument('label')
sub.add_parser('list')
revoke=sub.add_parser('revoke'); revoke.add_argument('user_id')
args=parser.parse_args()
server.initialize()
with server.connect() as db:
    if args.command=='create':
        identifier,token=database.create_user(db,args.label)
        print('用户 ID：',identifier); print('独立同步密钥（仅显示一次）：',token)
    elif args.command=='list':
        for row in db.execute('SELECT id,label,disabled,created_at FROM users'):
            print(row['id'],row['label'],'disabled' if row['disabled'] else 'active')
    else:
        db.execute('UPDATE users SET disabled=1 WHERE id=?',(args.user_id,))
        db.execute('DELETE FROM sessions WHERE user_id=?',(args.user_id,))
        print('访问已撤销；数据库内容保留供备份/恢复。')
