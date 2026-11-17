import './style.css';
export const metadata = {title:'LIAR GAME | 온라인 라이어 게임',description:'8명의 참가자와 2명의 MC가 함께하는 실시간 라이어 게임'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="ko"><body>{children}</body></html>}
