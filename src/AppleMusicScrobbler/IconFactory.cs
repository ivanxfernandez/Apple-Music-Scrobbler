using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace AppleMusicScrobbler
{
    // Draws the app icon (a white note on a coloured circle). Kept to C# 5 syntax so
    // tools/make-icon.ps1 can compile it with Windows PowerShell to produce app.ico.
    public static class IconFactory
    {
        public static readonly Color Red = Color.FromArgb(213, 16, 7);      // Last.fm red
        public static readonly Color Grey = Color.FromArgb(128, 128, 128);  // paused

        public static Bitmap DrawBitmap(Color background, int size)
        {
            var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.Clear(Color.Transparent);

                using (var brush = new SolidBrush(background))
                    g.FillEllipse(brush, 0f, 0f, size - 0.5f, size - 0.5f);

                float s = size;
                float stem = Math.Max(1.5f, s * 0.065f);
                float headW = s * 0.21f, headH = s * 0.16f;
                PointF head1 = new PointF(s * 0.24f, s * 0.60f);   // top-left corners of the note heads
                PointF head2 = new PointF(s * 0.55f, s * 0.53f);
                float stem1X = head1.X + headW - stem, stem2X = head2.X + headW - stem;
                float beamTop1 = s * 0.25f, beamTop2 = s * 0.18f, beamH = s * 0.11f;

                using (var white = new SolidBrush(Color.White))
                {
                    g.FillEllipse(white, head1.X, head1.Y, headW, headH);
                    g.FillEllipse(white, head2.X, head2.Y, headW, headH);
                    g.FillRectangle(white, stem1X, beamTop1, stem, head1.Y + headH * 0.5f - beamTop1);
                    g.FillRectangle(white, stem2X, beamTop2, stem, head2.Y + headH * 0.5f - beamTop2);
                    g.FillPolygon(white, new[]
                    {
                        new PointF(stem1X, beamTop1),
                        new PointF(stem2X + stem, beamTop2),
                        new PointF(stem2X + stem, beamTop2 + beamH),
                        new PointF(stem1X, beamTop1 + beamH),
                    });
                }
            }
            return bmp;
        }

        public static Icon CreateIcon(Color background, int size)
        {
            using (var bmp = DrawBitmap(background, size))
                return Icon.FromHandle(bmp.GetHicon());
        }
    }
}
